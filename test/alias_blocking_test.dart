import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aegis_net/src/bridge/aegis_bridge.dart';
import 'package:aegis_net/src/i18n/app_strings.dart';
import 'package:aegis_net/src/providers/block_reason.dart';
import 'package:aegis_net/src/providers/theme_provider.dart';
import 'package:aegis_net/src/providers/vpn_provider.dart';
import 'package:aegis_net/src/screens/settings_screen.dart';
import 'package:aegis_net/src/services/config_sync_service.dart';

const _channel = MethodChannel('com.aegisnet/vpn');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final engineFlag = <bool>[];

  setUp(() {
    AppStrings.lang = 'en';
    SharedPreferences.setMockInitialValues({});
    AegisBridge.debugResetEngine();
    engineFlag.clear();
    AegisBridge.debugSetAliasBlockingOverride = engineFlag.add;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'getVpnDiagnostics') {
        return <String, dynamic>{'sdkInt': 34};
      }
      return null;
    });
  });

  tearDown(() {
    AegisBridge.debugSetAliasBlockingOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('alias blocking defaults on, reaches the engine, and is saved',
      () async {
    final vpn = VpnProvider(enableSimulation: false);
    await vpn.ready;
    expect(vpn.blockAliasTrackers, isTrue);
    expect(engineFlag, [true]);

    await vpn.setBlockAliasTrackers(false);
    expect(vpn.blockAliasTrackers, isFalse);
    expect(engineFlag.last, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('block_cname_trackers'), isFalse);
    vpn.dispose();
  });

  test('a saved off value is restored and pushed to the engine', () async {
    SharedPreferences.setMockInitialValues({'block_cname_trackers': false});
    final vpn = VpnProvider(enableSimulation: false);
    await vpn.ready;
    expect(vpn.blockAliasTrackers, isFalse);
    expect(engineFlag, [false]);
    vpn.dispose();
  });

  test('the setting travels in a backup', () async {
    SharedPreferences.setMockInitialValues({'block_cname_trackers': false});
    final json = await ConfigSyncService.exportConfigToJson();
    expect(jsonDecode(json)['block_cname_trackers'], isFalse);

    SharedPreferences.setMockInitialValues({});
    expect(await ConfigSyncService.importConfigFromJson(json), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('block_cname_trackers'), isFalse);
  });

  test('the log names the tracker a blocked alias pointed to', () {
    final item = DnsLogItem.fromEngine({
      'id': 3,
      'timestamp': 1760000000,
      'domain': 'metrics.shop.example',
      'blocked': true,
      'reason': 'alias',
      'alias_of': 'c.tracker.example',
      'list': 'pgl_yoyo',
    });
    expect(item.aliasOf, 'c.tracker.example');
    expect(item.reasonText, 'Blocked: alias of c.tracker.example');
    for (final lang in AppStrings.languages) {
      AppStrings.lang = lang;
      expect(
          describeReason(
              blocked: true, reason: 'alias', aliasOf: 'c.tracker.example'),
          contains('c.tracker.example'),
          reason: lang);
    }
  });

  testWidgets('the settings switch turns alias blocking off', (tester) async {
    final vpn = VpnProvider(enableSimulation: false);
    await tester.runAsync(() => vpn.ready);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: vpn),
          ChangeNotifierProvider.value(value: ThemeProvider()),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final finder = find.byKey(const Key('cname_switch'));
    await tester.scrollUntilVisible(finder, 300,
        scrollable: find.byType(Scrollable).first);
    expect(tester.widget<Switch>(finder).value, isTrue);
    expect(find.text("Block trackers hidden behind a site's own address"),
        findsOneWidget);

    await tester.tap(finder);
    await tester.pumpAndSettle();
    expect(vpn.blockAliasTrackers, isFalse);
    expect(engineFlag.last, isFalse);
    vpn.dispose();
  });
}
