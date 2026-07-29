import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aegis_net/src/bridge/aegis_bridge.dart';
import 'package:aegis_net/src/providers/vpn_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AegisNet Unit Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
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

      provider.pauseProtection(const Duration(minutes: 5));
      expect(provider.isPaused, isTrue);
      expect(provider.isVpnActive, isFalse);

      provider.resumeProtection();
      expect(provider.isPaused, isFalse);
      expect(provider.isVpnActive, isTrue);
      provider.dispose();
    });
  });
}
