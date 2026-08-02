import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service to generate and install Encrypted DNS (.mobileconfig) profiles on iOS
/// without requiring a $99/yr Apple Developer Account / Network Extensions entitlement.
class IosDohProfileService {
  static const MethodChannel _vpnChannel = MethodChannel('com.aegisnet/vpn');
  static HttpServer? _localServer;

  /// Generate Apple .mobileconfig XML string for Encrypted DNS (DoH)
  static String generateMobileConfigXml({
    required String dohServerUrl,
    String identifier = 'com.aegisnet.dns.profile',
    String displayName = 'AegisNet Encrypted DNS',
  }) {
    final cleanUrl =
        dohServerUrl.isEmpty ? 'https://1.1.1.1/dns-query' : dohServerUrl;

    return '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.1.dtd">
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
                <string>$cleanUrl</string>
            </dict>
            <key>PayloadDescription</key>
            <string>Configures Encrypted DNS (DoH) for AegisNet Privacy Shield</string>
            <key>PayloadDisplayName</key>
            <string>$displayName</string>
            <key>PayloadIdentifier</key>
            <string>$identifier</string>
            <key>PayloadType</key>
            <string>com.apple.dnsSettings.managed</string>
            <key>PayloadUUID</key>
            <string>E7A69156-4271-4C5C-9A5A-4A732E958055</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
        </dict>
    </array>
    <key>PayloadDescription</key>
    <string>Enables AegisNet Encrypted DNS Firewall on iOS</string>
    <key>PayloadDisplayName</key>
    <string>$displayName</string>
    <key>PayloadIdentifier</key>
    <string>com.aegisnet.profile</string>
    <key>PayloadOrganization</key>
    <string>AegisNet</string>
    <key>PayloadRemovalDisallowed</key>
    <false/>
    <key>PayloadType</key>
    <string>Configuration</string>
    <key>PayloadUUID</key>
    <string>B4C25191-76A9-4E6D-A2BF-15D397C118B8</string>
    <key>PayloadVersion</key>
    <integer>1</integer>
</dict>
</plist>''';
  }

  /// Installs DoH Profile on iOS without requiring $99/yr NetworkExtension entitlement
  static Future<bool> installProfile(
      {String dohUrl = 'https://1.1.1.1/dns-query'}) async {
    if (kIsWeb) return false;

    // Try native iOS Swift handler first
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        final bool res =
            await _vpnChannel.invokeMethod('installMobileConfigProfile', {
          'dohUrl': dohUrl,
        });
        if (res) return true;
      } catch (_) {}
    }

    // Fallback: Start local HTTP server in Dart and serve profile payload
    try {
      await stopLocalServer();
      _localServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 8899);
      final xml = generateMobileConfigXml(dohServerUrl: dohUrl);

      _localServer?.listen((HttpRequest request) {
        request.response.headers.contentType =
            ContentType('application', 'x-apple-aspen-config');
        request.response.write(xml);
        request.response.close();
      });

      const String profileUrl =
          'http://127.0.0.1:8899/aegis_profile.mobileconfig';
      try {
        await _vpnChannel.invokeMethod('openUrl', {'url': profileUrl});
      } catch (_) {}
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> stopLocalServer() async {
    await _localServer?.close(force: true);
    _localServer = null;
  }
}
