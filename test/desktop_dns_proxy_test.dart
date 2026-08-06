import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:aegis_net/src/services/desktop_dns_proxy.dart';
import 'package:aegis_net/src/services/dns_message.dart';

/// A minimal well-formed query for `example.com` A/IN, transaction id 0xABCD.
Uint8List _query({int id = 0xABCD}) => Uint8List.fromList([
      id >> 8, id & 0xFF, // transaction id
      0x01, 0x00, // RD=1
      0x00, 0x01, // QDCOUNT = 1
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // AN/NS/AR = 0
      0x07, ...'example'.codeUnits,
      0x03, ...'com'.codeUnits,
      0x00, // root label
      0x00, 0x01, // QTYPE = A
      0x00, 0x01, // QCLASS = IN
    ]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await DesktopDnsProxy.stop();
  });

  group('DesktopDnsProxy', () {
    test('reports the port it actually bound, not the one it wanted', () async {
      // Port 0 lets the OS choose, which is the only way this test can run
      // anywhere. The production list is [53, 5300].
      final result = await DesktopDnsProxy.start(ports: const [0]);

      expect(result.running, isTrue);
      expect(result.port, isNotNull);
      expect(result.port, greaterThan(0));
      expect(DesktopDnsProxy.isRunning, isTrue);
    });

    test('a port nobody can bind is reported as a failure, not as running',
        () async {
      // 127.0.0.1 cannot bind a port already held by this test's own socket.
      final blocker =
          await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(blocker.close);

      final result = await DesktopDnsProxy.start(ports: [blocker.port]);

      expect(result.running, isFalse);
      expect(result.error, isNotNull);
      expect(DesktopDnsProxy.isRunning, isFalse);
    });

    test('every query gets an answer, even with no engine behind it', () async {
      // The desktop test host has no libaegis_core loaded, which is exactly the
      // case that must NOT go silent: a dropped datagram leaves the client
      // retrying until it times out.
      final started = await DesktopDnsProxy.start(ports: const [0]);
      expect(started.running, isTrue);

      final client =
          await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(client.close);

      final answer = Completer<Datagram>();
      client.listen((event) {
        if (event != RawSocketEvent.read) return;
        final d = client.receive();
        if (d != null && !answer.isCompleted) answer.complete(d);
      });

      client.send(_query(), InternetAddress.loopbackIPv4, started.port!);

      final reply = await answer.future.timeout(const Duration(seconds: 5));
      final data = reply.data;

      expect(data.length, greaterThanOrEqualTo(12));
      expect(data[0], 0xAB, reason: 'transaction id must be echoed');
      expect(data[1], 0xCD, reason: 'transaction id must be echoed');
      expect(data[2] & 0x80, 0x80, reason: 'QR bit must mark this a response');
    });

    test('stop releases the port so a restart can take it again', () async {
      final first = await DesktopDnsProxy.start(ports: const [0]);
      final port = first.port!;
      await DesktopDnsProxy.stop();

      expect(DesktopDnsProxy.isRunning, isFalse);

      final again = await DesktopDnsProxy.start(ports: [port]);
      expect(again.running, isTrue, reason: 'port was not released');
      expect(again.port, port);
    });
  });

  group('SERVFAIL fallback', () {
    test('echoes the question and sets RCODE 2 with no records', () {
      final reply = DnsMessage.buildServfail(_query());

      expect(reply, isNotNull);
      expect(reply![0], 0xAB);
      expect(reply[1], 0xCD);
      expect(reply[2] & 0x80, 0x80);
      expect(reply[3] & 0x0F, 0x02);
      for (final i in [6, 7, 8, 9, 10, 11]) {
        expect(reply[i], 0, reason: 'record counts must be zeroed');
      }
      // 12 byte header + 13 byte QNAME + 4 byte QTYPE/QCLASS
      expect(reply.length, 29);
    });

    test('refuses to invent a response for a malformed query', () {
      expect(DnsMessage.buildServfail(Uint8List(0)), isNull);
      expect(DnsMessage.buildServfail(Uint8List(8)), isNull);

      // QDCOUNT = 0: there is no question to echo back.
      final noQuestion = Uint8List.fromList(
          [0x00, 0x01, 0x01, 0x00, 0x00, 0x00, 0, 0, 0, 0, 0, 0]);
      expect(DnsMessage.buildServfail(noQuestion), isNull);

      // Label length runs past the end of the buffer.
      final truncated =
          Uint8List.fromList([0, 1, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0x3F, 0x61]);
      expect(DnsMessage.buildServfail(truncated), isNull);
    });
  });
}
