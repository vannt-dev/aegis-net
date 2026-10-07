import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aegis_net/src/bridge/aegis_bridge.dart';
import 'package:aegis_net/src/i18n/app_strings.dart';
import 'package:aegis_net/src/providers/app_info.dart';
import 'package:aegis_net/src/providers/theme_provider.dart';
import 'package:aegis_net/src/providers/vpn_provider.dart';
import 'package:aegis_net/src/screens/analytics_screen.dart';

const _chrome =
    AppInfo(uid: 10123, packageName: 'com.android.chrome', label: 'Chrome');
const _maps =
    AppInfo(uid: 10456, packageName: 'com.google.maps', label: 'Maps');

/// What the engine was last told, and what the platform says about packages.
class _Platform {
  final List<List<int>> pushed = [];
  Map<String, int>? installed = {
    'com.android.chrome': 10123,
    'com.google.maps': 10456,
  };

  void install() {
    AegisBridge.debugSetBlockedUidsOverride = (uids) => pushed.add(uids);
    AegisBridge.debugResolvePackageUidsOverride = (packages) async {
      final known = installed;
      if (known == null) throw StateError('channel down');
      return {
        for (final name in packages)
          if (known.containsKey(name)) name: known[name]!,
      };
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Platform platform;

  setUp(() {
    AppStrings.lang = 'en';
    SharedPreferences.setMockInitialValues({});
    platform = _Platform()..install();
  });

  tearDown(() {
    AegisBridge.debugSetBlockedUidsOverride = null;
    AegisBridge.debugResolvePackageUidsOverride = null;
  });

  VpnProvider provider({int sdk = 34}) {
    final vpn = VpnProvider(enableSimulation: false);
    addTearDown(vpn.dispose);
    vpn.debugSetAndroidSdk(sdk);
    return vpn;
  }

  group('blocking an app', () {
    test('hands its UID to the engine and remembers the package', () async {
      final vpn = provider();

      await vpn.setAppBlocked(_chrome, true);

      expect(vpn.isUidBlocked(10123), isTrue);
      expect(vpn.isUidBlocked(10456), isFalse);
      expect(vpn.blockedApps, ['com.android.chrome']);
      expect(platform.pushed.last, [10123]);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('blocked_apps'), ['com.android.chrome']);
    });

    test('allowing it again takes the UID back out', () async {
      final vpn = provider();
      await vpn.setAppBlocked(_chrome, true);
      await vpn.setAppBlocked(_maps, true);
      expect(platform.pushed.last, [10123, 10456]);

      await vpn.setAppBlocked(_chrome, false);

      expect(vpn.isUidBlocked(10123), isFalse);
      expect(vpn.isUidBlocked(10456), isTrue);
      expect(platform.pushed.last, [10456]);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('blocked_apps'), ['com.google.maps']);
    });

    test('the OS, unnamed apps and old Android versions cannot be blocked',
        () async {
      final vpn = provider();
      const system =
          AppInfo(uid: 1000, packageName: 'android', label: 'Android');
      const unnamed = AppInfo(uid: 10999);

      expect(vpn.canBlockApp(system), isFalse);
      expect(vpn.canBlockApp(unnamed), isFalse);
      expect(vpn.canBlockApp(_chrome), isTrue);
      await vpn.setAppBlocked(system, true);
      await vpn.setAppBlocked(unnamed, true);
      expect(vpn.blockedApps, isEmpty);
      expect(platform.pushed, isEmpty);

      // Android 9 names no app, so every query would arrive unattributed.
      final old = provider(sdk: 28);
      expect(old.canBlockApp(_chrome), isFalse);
      await old.setAppBlocked(_chrome, true);
      expect(old.blockedApps, isEmpty);
    });

    test('an app that moved to another UID is blocked under the new one',
        () async {
      final vpn = provider();
      await vpn.setAppBlocked(_chrome, true);

      // Reinstalled since: same package, new UID.
      platform.installed = {'com.android.chrome': 10777};
      await vpn.setAppBlocked(_maps, true);

      expect(vpn.isUidBlocked(10777), isTrue);
      expect(vpn.isUidBlocked(10123), isFalse);
      // Maps is not installed any more: it stays chosen but blocks nothing.
      expect(vpn.blockedApps, ['com.android.chrome', 'com.google.maps']);
      expect(platform.pushed.last, [10777]);
    });

    test('a failed look-up keeps what is in force', () async {
      final vpn = provider();
      await vpn.setAppBlocked(_chrome, true);

      platform.installed = null;
      await vpn.setAppBlocked(_maps, true);

      expect(vpn.isUidBlocked(10123), isTrue);
      expect(vpn.isUidBlocked(10456), isTrue);
      expect(platform.pushed.last, [10123, 10456]);
    });
  });

  group('the top apps list', () {
    Future<VpnProvider> pump(WidgetTester tester) async {
      final vpn = VpnProvider(enableSimulation: false);
      vpn.debugSetAndroidSdk(34);
      vpn.debugSetAppInfo({
        10123: _chrome,
        1000: const AppInfo(uid: 1000, packageName: 'android', sharedCount: 4),
      });
      vpn.debugSetStats({
        'top_apps': [
          {'uid': 10123, 'total': 8, 'blocked': 2},
          {'uid': 1000, 'total': 5, 'blocked': 0},
          {'uid': -1, 'total': 3, 'blocked': 0},
        ],
      });
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: vpn),
          ChangeNotifierProvider.value(value: ThemeProvider()),
        ],
        child: const MaterialApp(home: Scaffold(body: AnalyticsScreen())),
      ));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
          find.byKey(const Key('top_app_10123')), 200);
      return vpn;
    }

    testWidgets('offers the block action for apps only, and shows the result',
        (tester) async {
      final vpn = await pump(tester);
      try {
        final toggle = find.byKey(const Key('app_block_toggle_10123'));
        expect(toggle, findsOneWidget);
        expect(find.byKey(const Key('app_block_toggle_1000')), findsNothing);
        expect(find.byKey(const Key('app_block_toggle_-1')), findsNothing);
        expect(find.byKey(const Key('app_blocked_badge_10123')), findsNothing);

        await tester.tap(toggle);
        await tester.pumpAndSettle();

        expect(vpn.isUidBlocked(10123), isTrue);
        expect(
            find.byKey(const Key('app_blocked_badge_10123')), findsOneWidget);
        expect(find.textContaining('Chrome can no longer look up addresses'),
            findsOneWidget);
        // The row's own tap still opens the app's log, not the block action.
        expect(vpn.logAppFilter, isNull);

        await tester.tap(toggle);
        await tester.pumpAndSettle();

        expect(vpn.isUidBlocked(10123), isFalse);
        expect(find.byKey(const Key('app_blocked_badge_10123')), findsNothing);
        expect(
            find.text('Chrome can look up addresses again.'), findsOneWidget);
      } finally {
        vpn.dispose();
      }
    });
  });

  test('every language names the block action', () {
    for (final lang in ['en', 'vi', 'ko', 'ja']) {
      AppStrings.lang = lang;
      for (final key in [
        'app_block',
        'app_unblock',
        'app_blocked_badge',
        'app_blocked_notice',
        'app_unblocked_notice',
      ]) {
        expect(AppStrings.get(key), isNot(key), reason: '$lang/$key');
      }
      expect(AppStrings.get('app_blocked_notice'), contains('%s'));
      expect(AppStrings.get('app_unblocked_notice'), contains('%s'));
    }
    AppStrings.lang = 'en';
  });
}
