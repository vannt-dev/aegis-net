import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aegis_net/src/bridge/aegis_bridge.dart';
import 'package:aegis_net/src/providers/vpn_provider.dart';
import 'package:aegis_net/src/services/ios_doh_profile_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const vpnChannel = MethodChannel('com.aegisnet/vpn');

  /// Stands in for the native VpnManager/MainActivity handler. Without this the
  /// channel throws MissingPluginException and the provider tests would only be
  /// exercising the no-native-side fallback instead of the real path.
  void mockTunnel({required bool startSucceeds}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(vpnChannel, (MethodCall call) async {
      switch (call.method) {
        case 'startVpn':
          return startSucceeds;
        case 'stopVpn':
          return true;
        case 'isVpnPrepared':
          return true;
      }
      return null;
    });
  }

  group('AegisNet Unit Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockTunnel(startSucceeds: true);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(vpnChannel, null);
    });

    test('AegisBridge initial state & domain blocking logic', () {
      expect(AegisBridge.isDomainBlocked('doubleclick.net'), isTrue);
      expect(AegisBridge.isDomainBlocked('google.com'), isFalse);

      AegisBridge.addWhitelist('doubleclick.net');
      expect(AegisBridge.isDomainBlocked('doubleclick.net'), isFalse);

      AegisBridge.addBlacklist('google.com');
      expect(AegisBridge.isDomainBlocked('google.com'), isTrue);
    });

    test('Custom host mapping in AegisBridge and VpnProvider', () {
      final provider = VpnProvider(enableSimulation: false);
      provider.addCustomHost('myrouter.local', '192.168.1.1');
      expect(provider.customHosts['myrouter.local'], equals('192.168.1.1'));

      provider.removeCustomHost('myrouter.local');
      expect(provider.customHosts.containsKey('myrouter.local'), isFalse);
    });

    test('Schedule settings management in VpnProvider', () {
      final provider = VpnProvider(enableSimulation: false);
      expect(provider.scheduleEnabled, isFalse);

      provider.setSchedule(enabled: true, startHour: 23, endHour: 7);
      expect(provider.scheduleEnabled, isTrue);
      expect(provider.quietHoursStart, equals(23));
      expect(provider.quietHoursEnd, equals(7));
    });

    test('AegisBridge whitelist removal restores blocking', () {
      expect(AegisBridge.isDomainBlocked('aniview.com'), isTrue);

      AegisBridge.addWhitelist('aniview.com');
      expect(AegisBridge.isDomainBlocked('aniview.com'), isFalse);

      AegisBridge.removeWhitelist('aniview.com');
      expect(AegisBridge.isDomainBlocked('aniview.com'), isTrue);
    });

    test('AegisBridge fallback matches domains and subdomains, not substrings',
        () {
      // adnxs.com is a seeded fallback rule.
      expect(AegisBridge.isDomainBlocked('adnxs.com'), isTrue);
      expect(AegisBridge.isDomainBlocked('sub.adnxs.com'), isTrue);

      // 'myadnxs.com' merely CONTAINS the rule as a substring; it is a different
      // registrable domain and must NOT be blocked.
      expect(AegisBridge.isDomainBlocked('myadnxs.com'), isFalse);
    });

    test('VpnProvider state management & toggle', () async {
      final provider = VpnProvider(enableSimulation: false);
      expect(provider.isVpnActive, isFalse);

      await provider.toggleVpn();
      expect(provider.isVpnActive, isTrue);

      // pauseProtection/resumeProtection are async: they wait on the tunnel
      // actually stopping/starting before flipping the paused flag.
      await provider.pauseProtection(const Duration(minutes: 5));
      expect(provider.isPaused, isTrue);
      expect(provider.isVpnActive, isFalse);

      await provider.resumeProtection();
      expect(provider.isPaused, isFalse);
      expect(provider.isVpnActive, isTrue);
      provider.dispose();
    });

    test('toggleVpn stays off when the tunnel refuses to start', () async {
      mockTunnel(startSucceeds: false);
      final provider = VpnProvider(enableSimulation: false);

      await provider.toggleVpn();

      expect(provider.isVpnActive, isFalse);
      provider.dispose();
    });

    test('toggleVpn stays off when no native handler is registered', () async {
      // Reproduces the iOS bug where VpnManager never registers the channel:
      // the call throws MissingPluginException and nothing is filtering, so the
      // UI must not claim protection.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(vpnChannel, null);
      final provider = VpnProvider(enableSimulation: false);

      await provider.toggleVpn();

      expect(provider.isVpnActive, isFalse);
      provider.dispose();
    });

    test('VpnProvider persists Whitelist, Blacklist, and BypassApps', () async {
      final provider = VpnProvider(enableSimulation: false);

      provider.addWhitelistDomain('custom-white.com');
      provider.addBlacklistDomain('custom-black.com');
      provider.addBypassApp('com.example.bypass');

      expect(provider.whitelist, contains('custom-white.com'));
      expect(provider.blacklist, contains('custom-black.com'));
      expect(provider.bypassApps, contains('com.example.bypass'));

      provider.dispose();

      // Create new provider instance to test loading saved preferences
      final provider2 = VpnProvider(enableSimulation: false);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(provider2.whitelist, contains('custom-white.com'));
      expect(provider2.blacklist, contains('custom-black.com'));
      expect(provider2.bypassApps, contains('com.example.bypass'));
      provider2.dispose();
    });

    test('startVpn passes bypassApps in MethodChannel call', () async {
      List<dynamic>? passedBypassApps;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(vpnChannel, (MethodCall call) async {
        if (call.method == 'startVpn') {
          final args = call.arguments as Map<dynamic, dynamic>?;
          passedBypassApps = args?['bypassApps'] as List<dynamic>?;
          return true;
        }
        return true;
      });

      final provider = VpnProvider(enableSimulation: false);
      provider.addBypassApp('com.app.test');
      await provider.toggleVpn();

      expect(passedBypassApps, isNotNull);
      expect(passedBypassApps, contains('com.app.test'));
      provider.dispose();
    });

    test('a native start failure surfaces its reason instead of vanishing',
        () async {
      // The Android side answers with a PlatformException carrying the reason
      // the tunnel never came up (MIUI revoking consent, no vpndialogs, ...).
      // Swallowing it is what made the Xiaomi bug invisible: the toggle just
      // sat there with no explanation.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(vpnChannel, (MethodCall call) async {
        if (call.method == 'startVpn') {
          throw PlatformException(
            code: 'tunnel_not_established',
            message: 'establish() returned null',
          );
        }
        return true;
      });

      final provider = VpnProvider(enableSimulation: false);
      await provider.toggleVpn();

      expect(provider.isVpnActive, isFalse);
      expect(provider.lastError, isNotNull);
      expect(provider.lastError, contains('tunnel_not_established'));
      provider.dispose();
    });

    test('strict Private DNS is reported as bypassing the tunnel', () async {
      // "hostname" mode makes Android's resolver speak DoT straight to the
      // configured provider, ignoring the DNS server the tunnel advertises —
      // the tunnel is up and filtering nothing. MIUI users hit this often.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(vpnChannel, (MethodCall call) async {
        if (call.method == 'getVpnDiagnostics') {
          return <String, dynamic>{
            'privateDnsMode': 'hostname',
            'tunnelUp': true,
          };
        }
        return true;
      });

      final provider = VpnProvider(enableSimulation: false);
      await provider.toggleVpn();

      expect(provider.isVpnActive, isTrue);
      expect(provider.privateDnsBypass, isTrue);
      provider.dispose();
    });

    test('automatic and off Private DNS modes do not raise the warning',
        () async {
      // "opportunistic" probes DoT against the tunnel's own DNS server, which
      // does not answer on 853, so the resolver falls back to cleartext and
      // filtering still works. Warning about it would be a false alarm.
      for (final mode in ['off', 'opportunistic', null]) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(vpnChannel, (MethodCall call) async {
          if (call.method == 'getVpnDiagnostics') {
            return <String, dynamic>{'privateDnsMode': mode};
          }
          return true;
        });

        final provider = VpnProvider(enableSimulation: false);
        await provider.toggleVpn();

        expect(provider.privateDnsBypass, isFalse, reason: 'mode=$mode');
        provider.dispose();
      }
    });

    test('stopping the tunnel clears the Private DNS warning', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(vpnChannel, (MethodCall call) async {
        if (call.method == 'getVpnDiagnostics') {
          return <String, dynamic>{'privateDnsMode': 'hostname'};
        }
        return true;
      });

      final provider = VpnProvider(enableSimulation: false);
      await provider.toggleVpn();
      expect(provider.privateDnsBypass, isTrue);

      await provider.toggleVpn();

      expect(provider.isVpnActive, isFalse);
      expect(provider.privateDnsBypass, isFalse);
      provider.dispose();
    });

    test('a successful start clears a previous error', () async {
      final provider = VpnProvider(enableSimulation: false);

      await provider.toggleVpn();

      expect(provider.isVpnActive, isTrue);
      expect(provider.lastError, isNull);
      provider.dispose();
    });

    test('IosDohProfileService generates valid Apple .mobileconfig XML', () {
      final xml = IosDohProfileService.generateMobileConfigXml(
        dohServerUrl: 'https://dns.adguard-dns.com/dns-query',
      );
      expect(xml, contains('com.apple.dnsSettings.managed'));
      expect(xml, contains('https://dns.adguard-dns.com/dns-query'));
      expect(xml, contains('AegisNet Encrypted DNS'));

      // Apple's DTD is PropertyList-1.0.dtd — a bogus 1.0.1 URL was shipped
      // in both the Dart and Swift copies of this payload.
      expect(xml, contains('PropertyList-1.0.dtd'));
      expect(xml, isNot(contains('PropertyList-1.0.1.dtd')));
    });

    test('mobileconfig escapes XML metacharacters in the DoH URL', () {
      // Query parameters on DoH endpoints are common and '&' would otherwise
      // produce a plist iOS rejects as malformed.
      final xml = IosDohProfileService.generateMobileConfigXml(
        dohServerUrl: 'https://doh.example/dns-query?a=1&b=2',
      );

      expect(xml, contains('https://doh.example/dns-query?a=1&amp;b=2'));
      expect(xml, isNot(contains('?a=1&b=2')));
    });

    test('mobileconfig UUIDs are stable per endpoint and differ across them',
        () {
      final a = IosDohProfileService.generateMobileConfigXml(
          dohServerUrl: 'https://1.1.1.1/dns-query');
      final again = IosDohProfileService.generateMobileConfigXml(
          dohServerUrl: 'https://1.1.1.1/dns-query');
      final b = IosDohProfileService.generateMobileConfigXml(
          dohServerUrl: 'https://dns.quad9.net/dns-query');

      expect(a, equals(again));
      expect(a, isNot(equals(b)));

      // Payload and top-level UUIDs must not collide with each other.
      expect(IosDohProfileService.deriveUuid('dns:x'),
          isNot(IosDohProfileService.deriveUuid('root:x')));
      expect(
        IosDohProfileService.deriveUuid('dns:x'),
        matches(RegExp(r'^[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}$')),
      );
    });

    test('empty DoH URL falls back to the default endpoint', () {
      final xml =
          IosDohProfileService.generateMobileConfigXml(dohServerUrl: '   ');
      expect(xml, contains(IosDohProfileService.defaultDohUrl));
    });

    test('loopback profile server serves the payload then shuts down',
        () async {
      // TestWidgetsFlutterBinding installs HttpOverrides.global so every
      // request 400s. Lift it for the duration of this test so the client can
      // talk to its own loopback socket. Nothing leaves the machine.
      final savedOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      try {
        {
          final client = HttpClient();
          try {
            final url = await IosDohProfileService.serveProfile(
                dohUrl: 'https://1.1.1.1/dns-query');
            expect(url, isNotNull);
            expect(IosDohProfileService.isServing, isTrue);

            final response =
                await (await client.getUrl(Uri.parse(url!))).close();
            final body = await response.transform(const Utf8Decoder()).join();

            expect(
                response.headers.contentType?.subType, 'x-apple-aspen-config');
            expect(body, contains('com.apple.dnsSettings.managed'));

            // An unrelated path must not serve the profile.
            final miss = await (await client.getUrl(Uri.parse(
                    url.replaceFirst(IosDohProfileService.profilePath, '/x'))))
                .close();
            expect(miss.statusCode, HttpStatus.notFound);
            await miss.drain<void>();
          } finally {
            client.close(force: true);
            await IosDohProfileService.stopLocalServer();
          }

          expect(IosDohProfileService.isServing, isFalse);
        }
      } finally {
        HttpOverrides.global = savedOverrides;
      }
    });

    test('installProfile is a no-op off iOS and leaves no socket behind',
        () async {
      // debugDefaultTargetPlatformOverride is null here, so the host platform
      // (never iOS in CI) applies.
      expect(await IosDohProfileService.installProfile(), isFalse);
      expect(IosDohProfileService.isServing, isFalse);
    });
  });
}
