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
