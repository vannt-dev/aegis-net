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

    test('IosDohProfileService generates valid Apple .mobileconfig XML', () {
      final xml = IosDohProfileService.generateMobileConfigXml(
        dohServerUrl: 'https://dns.adguard-dns.com/dns-query',
      );
      expect(xml, contains('com.apple.dnsSettings.managed'));
      expect(xml, contains('https://dns.adguard-dns.com/dns-query'));
      expect(xml, contains('AegisNet Encrypted DNS'));
    });
  });
}
