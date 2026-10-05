import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aegis_net/src/bridge/aegis_bridge.dart';
import 'package:aegis_net/src/i18n/app_strings.dart';
import 'package:aegis_net/src/providers/app_info.dart';
import 'package:aegis_net/src/providers/vpn_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppStrings.lang = 'en';
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => AegisBridge.debugResolveAppsOverride = null);

  group('AppInfo.displayName', () {
    test('uses the label, with the number of other packages sharing the uid',
        () {
      expect(const AppInfo(uid: 10123, label: 'Chrome').displayName, 'Chrome');
      expect(
          const AppInfo(uid: 10500, label: 'Maps', sharedCount: 2).displayName,
          'Maps (+2)');
    });

    test('falls back to the package, then system, then the uid', () {
      expect(const AppInfo(uid: 10123, packageName: 'com.example').displayName,
          'com.example');
      expect(const AppInfo(uid: 1000).displayName, 'Android system');
      expect(const AppInfo(uid: 10123).displayName, 'UID 10123');
      expect(const AppInfo(uid: AppInfo.unknownUid).displayName, 'Unknown app');
    });

    test('reads the channel map', () {
      final info = AppInfo.fromMap({
        'uid': 10123,
        'package': 'com.android.chrome',
        'label': 'Chrome',
        'isSystem': false,
        'sharedCount': 0,
      });
      expect(info.uid, 10123);
      expect(info.packageName, 'com.android.chrome');
      expect(info.displayName, 'Chrome');
    });
  });

  group('VpnProvider per-app data', () {
    test('reads top_apps from the engine stats', () {
      final vpn = VpnProvider(enableSimulation: false);
      vpn.debugSetStats({
        'top_apps': [
          {'uid': 10123, 'total': 8, 'blocked': 2},
          {'uid': -1, 'total': 3, 'blocked': 0},
        ],
      });
      expect(vpn.topApps.map((a) => a.uid), [10123, -1]);
      expect(vpn.topApps.first.blockRate, 0.25);
    });

    test('top apps are empty when the engine has none', () {
      final vpn = VpnProvider(enableSimulation: false);
      vpn.debugSetStats({'total_queries': 3});
      expect(vpn.topApps, isEmpty);
    });

    test('a log item without a uid is unknown', () {
      final item = DnsLogItem(
          id: '1',
          domain: 'a.example',
          isBlocked: false,
          timestamp: DateTime(2026));
      expect(item.uid, AppInfo.unknownUid);
    });

    test('resolves each uid once and never the unknown uid', () async {
      final asked = <List<int>>[];
      AegisBridge.debugResolveAppsOverride = (uids) async {
        asked.add(List.of(uids));
        return {for (final u in uids) u: AppInfo(uid: u, label: 'App $u')};
      };
      final vpn = VpnProvider(enableSimulation: false);
      vpn.debugSetStats({
        'top_apps': [
          {'uid': 10123, 'total': 1, 'blocked': 0},
          {'uid': -1, 'total': 1, 'blocked': 0},
        ],
      });
      vpn.debugSetLogs([
        DnsLogItem(
            id: '1',
            domain: 'a',
            isBlocked: false,
            timestamp: DateTime(2026),
            uid: 10123),
        DnsLogItem(
            id: '2',
            domain: 'b',
            isBlocked: false,
            timestamp: DateTime(2026),
            uid: 10456),
      ]);

      await Future.wait([vpn.debugResolveApps(), vpn.debugResolveApps()]);
      await vpn.debugResolveApps();

      expect(asked, [
        [10123, 10456]
      ]);
      expect(vpn.appInfo(10456).displayName, 'App 10456');
      expect(vpn.appInfo(-1).displayName, 'Unknown app');
    });

    test('per-app support follows the Android version', () {
      final vpn = VpnProvider(enableSimulation: false);
      expect(vpn.showsPerAppUi, isFalse);
      vpn.debugSetAndroidSdk(28);
      expect(vpn.showsPerAppUi, isTrue);
      expect(vpn.perAppSupported, isFalse);
      vpn.debugSetAndroidSdk(29);
      expect(vpn.perAppSupported, isTrue);
    });

    test('the log app filter can be set and cleared', () {
      final vpn = VpnProvider(enableSimulation: false);
      vpn.setLogAppFilter(10123);
      expect(vpn.logAppFilter, 10123);
      vpn.setLogAppFilter(null);
      expect(vpn.logAppFilter, isNull);
    });
  });

  group('review fixes', () {
    test('a shared system uid is the system, not one of its packages', () {
      expect(
          const AppInfo(uid: 1000, label: 'Settings', sharedCount: 47)
              .displayName,
          'Android system (+47)');
      expect(const AppInfo(uid: 2000, label: 'Shell').displayName, 'Shell');
    });

    test('a failed lookup is asked again on the next refresh', () async {
      var calls = 0;
      AegisBridge.debugResolveAppsOverride = (uids) async {
        calls += 1;
        if (calls == 1) throw Exception('channel down');
        return {for (final u in uids) u: AppInfo(uid: u, label: 'Chrome')};
      };
      final vpn = VpnProvider(enableSimulation: false);
      vpn.debugSetStats({
        'top_apps': [
          {'uid': 10123, 'total': 1, 'blocked': 0},
        ],
      });

      await vpn.debugResolveApps();
      expect(vpn.appInfo(10123).displayName, 'UID 10123');
      await vpn.debugResolveApps();
      expect(calls, 2);
      expect(vpn.appInfo(10123).displayName, 'Chrome');
    });

    test('a uid the platform could not name is asked again after a minute',
        () async {
      final asked = <int>[];
      AegisBridge.debugResolveAppsOverride = (uids) async {
        asked.addAll(uids);
        return {};
      };
      var now = DateTime(2026, 10, 4, 12);
      final vpn = VpnProvider(enableSimulation: false)..debugNow = () => now;
      vpn.debugSetStats({
        'top_apps': [
          {'uid': 10123, 'total': 1, 'blocked': 0},
        ],
      });

      await vpn.debugResolveApps();
      await vpn.debugResolveApps();
      expect(asked, [10123]);

      now = now.add(const Duration(seconds: 61));
      await vpn.debugResolveApps();
      expect(asked, [10123, 10123]);
    });
  });
}
