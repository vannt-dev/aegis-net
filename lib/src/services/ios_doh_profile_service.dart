import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Generates and installs an Encrypted DNS (.mobileconfig) profile on iOS
/// without requiring a $99/yr Apple Developer Account / Network Extensions
/// entitlement.
///
/// iOS refuses to install a profile handed to it as a `file:` URL, so the
/// profile is always served from a loopback HTTP server and opened in Safari,
/// which hands it to Settings. This class owns the only copy of the payload
/// XML — the native side just opens the URL it is given.
class IosDohProfileService {
  static const MethodChannel _vpnChannel = MethodChannel('com.aegisnet/vpn');

  static const String defaultDohUrl = 'https://1.1.1.1/dns-query';

  /// Port Safari is pointed at. Falls back to an ephemeral port when taken.
  static const int preferredPort = 8899;

  /// How long the profile stays downloadable when Safari never fetches it —
  /// the user backed out of the confirmation dialog, so drop the socket.
  static const Duration serverLifetime = Duration(minutes: 2);

  /// Grace period after the payload has actually been handed over. Safari has
  /// the file at that point; Settings reads it from its own copy.
  static const Duration lingerAfterDownload = Duration(seconds: 30);

  static const String profilePath = '/aegis_profile.mobileconfig';

  static HttpServer? _localServer;
  static Timer? _shutdownTimer;

  /// Test seam: the loopback server is unreachable from the iOS simulator's
  /// Safari in widget tests, so tests drive [generateMobileConfigXml] directly.
  @visibleForTesting
  static bool get isServing => _localServer != null;

  /// XML character data escaping. A user-supplied DoH URL carrying `&` (query
  /// parameters are common on DoH endpoints) would otherwise produce a plist
  /// iOS rejects as malformed.
  static String escapeXml(String raw) => raw
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  /// Stable UUID derived from [seed]. iOS keys a profile by its
  /// PayloadIdentifier, but reuses the UUID to detect "same payload" — deriving
  /// it from the DoH URL means switching upstream produces a genuinely new
  /// payload instead of silently reusing the previous one.
  static String deriveUuid(String seed) {
    const int mask = 0xFFFFFFFF;
    final data = utf8.encode(seed);
    final bytes = <int>[];

    // Four FNV-1a lanes, each with its own offset basis, give the 16 bytes.
    for (var lane = 0; lane < 4; lane++) {
      var hash = (0x811C9DC5 ^ (lane * 0x9E3779B1)) & mask;
      for (final unit in data) {
        hash = (hash ^ unit) & mask;
        hash = (hash * 0x01000193) & mask;
      }
      bytes.addAll([
        (hash >> 24) & 0xFF,
        (hash >> 16) & 0xFF,
        (hash >> 8) & 0xFF,
        hash & 0xFF,
      ]);
    }

    bytes[6] = (bytes[6] & 0x0F) | 0x40; // RFC 4122 version nibble
    bytes[8] = (bytes[8] & 0x3F) | 0x80; // RFC 4122 variant bits

    final hex = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  /// Apple .mobileconfig XML for Encrypted DNS (DoH).
  static String generateMobileConfigXml({
    required String dohServerUrl,
    String identifier = 'com.aegisnet.dns.profile',
    String displayName = 'AegisNet Encrypted DNS',
  }) {
    final cleanUrl =
        dohServerUrl.trim().isEmpty ? defaultDohUrl : dohServerUrl.trim();
    final url = escapeXml(cleanUrl);
    final name = escapeXml(displayName);
    final payloadId = escapeXml(identifier);

    return '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>PayloadContent</key>
    <array>
        <dict>
            <key>DNSSettings</key>
            <dict>
                <key>DNSProtocol</key>
                <string>HTTPS</string>
                <key>ServerURL</key>
                <string>$url</string>
            </dict>
            <key>PayloadDescription</key>
            <string>Configures Encrypted DNS (DoH) for AegisNet Privacy Shield</string>
            <key>PayloadDisplayName</key>
            <string>$name</string>
            <key>PayloadIdentifier</key>
            <string>$payloadId</string>
            <key>PayloadType</key>
            <string>com.apple.dnsSettings.managed</string>
            <key>PayloadUUID</key>
            <string>${deriveUuid('dns:$cleanUrl')}</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
        </dict>
    </array>
    <key>PayloadDescription</key>
    <string>Enables AegisNet Encrypted DNS Firewall on iOS</string>
    <key>PayloadDisplayName</key>
    <string>$name</string>
    <key>PayloadIdentifier</key>
    <string>com.aegisnet.profile</string>
    <key>PayloadOrganization</key>
    <string>AegisNet</string>
    <key>PayloadRemovalDisallowed</key>
    <false/>
    <key>PayloadType</key>
    <string>Configuration</string>
    <key>PayloadUUID</key>
    <string>${deriveUuid('root:$cleanUrl')}</string>
    <key>PayloadVersion</key>
    <integer>1</integer>
</dict>
</plist>''';
  }

  /// Serves the profile on loopback and returns the URL Safari should open,
  /// or null when no socket could be bound.
  static Future<String?> serveProfile({String dohUrl = defaultDohUrl}) async {
    await stopLocalServer();

    HttpServer? server;
    for (final port in [preferredPort, 0]) {
      try {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
        break;
      } on SocketException catch (e) {
        debugPrint('[AegisDoH] bind on port $port failed: ${e.message}');
      }
    }
    if (server == null) return null;

    _localServer = server;
    final xml = generateMobileConfigXml(dohServerUrl: dohUrl);

    server.listen((HttpRequest request) async {
      if (request.uri.path != profilePath) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      request.response.headers.contentType =
          ContentType('application', 'x-apple-aspen-config');
      request.response.headers.set(
        'Content-Disposition',
        'attachment; filename="aegis_profile.mobileconfig"',
      );
      request.response.write(xml);
      await request.response.close();

      // Safari has the payload now; keep the socket briefly for a retry.
      if (request.method == 'GET') _armShutdown(lingerAfterDownload);
    }, onError: (Object e) => debugPrint('[AegisDoH] serve error: $e'));

    _armShutdown(serverLifetime);
    return 'http://127.0.0.1:${server.port}$profilePath';
  }

  /// Generates the profile and hands it to Safari, which routes it to
  /// Settings > Profile Downloaded. iOS-only.
  static Future<bool> installProfile({String dohUrl = defaultDohUrl}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return false;

    final url = await serveProfile(dohUrl: dohUrl);
    if (url == null) return false;

    try {
      final opened = await _vpnChannel.invokeMethod<bool>('openUrl', {
        'url': url,
      });
      if (opened == true) return true;
    } catch (e) {
      debugPrint('[AegisDoH] openUrl failed: $e');
    }

    // Nothing is going to fetch it — do not leave the socket behind.
    await stopLocalServer();
    return false;
  }

  static void _armShutdown(Duration delay) {
    _shutdownTimer?.cancel();
    _shutdownTimer = Timer(delay, stopLocalServer);
  }

  static Future<void> stopLocalServer() async {
    _shutdownTimer?.cancel();
    _shutdownTimer = null;
    final server = _localServer;
    _localServer = null;
    await server?.close(force: true);
  }
}
