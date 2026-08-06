import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../bridge/ffi_native.dart';

/// Outcome of starting the proxy. [port] is the port actually bound, which is
/// not necessarily the one that was asked for — the caller has to tell the user
/// the truth about where it ended up.
class DesktopProxyStatus {
  const DesktopProxyStatus({required this.running, this.port, this.error});

  final bool running;
  final int? port;
  final String? error;

  /// Only a resolver on port 53 can be entered into an operating system's DNS
  /// settings, which take a bare IP address with no port. Anywhere else the
  /// proxy is reachable only by tools that let you name a port.
  bool get usableAsSystemResolver => running && port == 53;
}

/// A real local DNS resolver for desktop builds.
///
/// Desktop has no VpnService equivalent, so nothing can capture the machine's
/// DNS traffic automatically. This listens on loopback and answers queries
/// through the same Rust engine the mobile tunnels use; pointing the operating
/// system at it is the user's step, and the UI has to say so rather than
/// claiming the machine is protected.
class DesktopDnsProxy {
  /// Port 53 first, because that is the only one an OS DNS setting can reach.
  /// 5300 is the fallback for unprivileged runs — deliberately not 5353, which
  /// mDNSResponder and avahi already hold on macOS and most Linux desktops.
  static const List<int> defaultPorts = [53, 5300];

  static RawDatagramSocket? _socket;
  static _EngineWorker? _worker;

  static bool get isRunning => _socket != null;

  /// Port currently being served, or null when stopped.
  static int? get port => _socket?.port;

  /// Binds the first port in [ports] that is free and starts answering queries.
  static Future<DesktopProxyStatus> start({
    List<int> ports = defaultPorts,
  }) async {
    await stop();

    RawDatagramSocket? socket;
    String? lastError;
    for (final candidate in ports) {
      try {
        socket = await RawDatagramSocket.bind(
          InternetAddress.loopbackIPv4,
          candidate,
          // Dart defaults this to true, which on Windows lets a second socket
          // bind a UDP port someone else already holds. The proxy would then
          // report success on a port where queries land on whichever socket the
          // OS picks. A taken port must fail so the next candidate is tried.
          reuseAddress: false,
        );
        break;
      } on SocketException catch (e) {
        // Port 53 needs root on macOS/Linux and may be held by a local resolver
        // anywhere; that is expected, not exceptional.
        lastError = 'port $candidate: ${e.osError?.message ?? e.message}';
        debugPrint('[AegisDesktop] bind failed on $lastError');
      }
    }

    if (socket == null) {
      return DesktopProxyStatus(
        running: false,
        error: lastError ?? 'no port could be bound',
      );
    }

    _socket = socket;
    _worker = await _EngineWorker.spawn();

    socket.listen(
      _onSocketEvent,
      onError: (Object e) => debugPrint('[AegisDesktop] socket error: $e'),
    );

    debugPrint(
        '[AegisDesktop] DNS proxy listening on 127.0.0.1:${socket.port}');
    return DesktopProxyStatus(running: true, port: socket.port);
  }

  static Future<void> stop() async {
    _socket?.close();
    _socket = null;
    await _worker?.dispose();
    _worker = null;
  }

  static void _onSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _socket?.receive();
    if (datagram == null || datagram.data.isEmpty) return;
    unawaited(_answer(datagram));
  }

  static Future<void> _answer(Datagram query) async {
    Uint8List? reply;
    try {
      reply = await _worker?.resolve(query.data);
    } catch (e) {
      debugPrint('[AegisDesktop] engine failed: $e');
    }

    // Never leave a query unanswered. Dropping it makes the client retry until
    // it times out with no clue that anything is wrong — the same silent
    // failure the tunnel was fixed for.
    reply ??= buildServfail(query.data);
    if (reply == null) return; // Not a DNS query we can even echo back.

    _socket?.send(reply, query.address, query.port);
  }

  /// Response echoing the request's header and question with RCODE 2
  /// (SERVFAIL) and no records. Null when [query] is not a well-formed query,
  /// since there would be nothing truthful to send.
  static Uint8List? buildServfail(Uint8List query) {
    final end = _questionEndOffset(query);
    if (end == null) return null;

    final reply = Uint8List.fromList(query.sublist(0, end));
    reply[2] = 0x81; // QR=1, RD=1
    reply[3] = 0x82; // RA=1, RCODE=2 (SERVFAIL)
    for (final i in [6, 7, 8, 9, 10, 11]) {
      reply[i] = 0; // AN / NS / AR counts
    }
    return reply;
  }

  /// Offset just past the first question (QNAME + QTYPE + QCLASS), mirroring
  /// `DnsFilterService::question_end_offset` on the Rust side.
  static int? _questionEndOffset(Uint8List buffer) {
    if (buffer.length < 12) return null;
    if ((buffer[4] << 8 | buffer[5]) == 0) return null; // QDCOUNT

    var offset = 12;
    while (true) {
      if (offset >= buffer.length) return null;
      final len = buffer[offset];
      if (len == 0) {
        offset += 1; // root label terminator
        break;
      }
      if (len > 63 || offset + 1 + len > buffer.length) return null;
      offset += 1 + len;
    }

    if (offset + 4 > buffer.length) return null;
    return offset + 4;
  }
}

/// Runs the engine on its own isolate.
///
/// `aegis_handle_dns_packet` blocks for the whole upstream DoH round trip, so
/// calling it on the isolate that drives the UI freezes the app for up to 2.5s
/// per cache miss. Function pointers are not shared across isolates, so the
/// worker opens the library itself; the engine's state lives in process-wide
/// Rust globals, so rules, cache and stats stay shared either way.
class _EngineWorker {
  _EngineWorker._(this._isolate, this._toWorker, this._fromWorker);

  final Isolate _isolate;
  final SendPort _toWorker;
  final ReceivePort _fromWorker;

  final Map<int, Completer<Uint8List?>> _pending = {};
  int _nextId = 0;

  static Future<_EngineWorker> spawn() async {
    final fromWorker = ReceivePort();
    final ready = Completer<SendPort>();

    final isolate = await Isolate.spawn(_main, fromWorker.sendPort);
    late final _EngineWorker worker;

    fromWorker.listen((message) {
      if (message is SendPort) {
        ready.complete(message);
        return;
      }
      if (message is List && message.length == 2) {
        worker._complete(message[0] as int, message[1] as Uint8List?);
      }
    });

    final toWorker = await ready.future;
    worker = _EngineWorker._(isolate, toWorker, fromWorker);
    return worker;
  }

  void _complete(int id, Uint8List? reply) {
    _pending.remove(id)?.complete(reply);
  }

  Future<Uint8List?> resolve(Uint8List query) {
    final id = _nextId++;
    final completer = Completer<Uint8List?>();
    _pending[id] = completer;
    _toWorker.send([id, query]);
    return completer.future;
  }

  Future<void> dispose() async {
    _fromWorker.close();
    _isolate.kill(priority: Isolate.immediate);
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.complete(null);
    }
    _pending.clear();
  }

  static void _main(SendPort toMain) {
    final fromMain = ReceivePort();
    toMain.send(fromMain.sendPort);

    // Each isolate needs its own handle on the shared library.
    AegisNativeBindings.initNativeLibrary();

    fromMain.listen((message) {
      if (message is! List || message.length != 2) return;
      final id = message[0] as int;
      final query = message[1] as Uint8List;
      toMain.send([id, AegisNativeBindings.handleDnsPacket(query)]);
    });
  }
}
