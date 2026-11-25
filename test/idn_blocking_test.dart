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

/// The optional switch that blocks look-alike international domain names.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final engineFlag = <bool>[];

  setUp(() {
    AppStrings.lang = 'en';
    SharedPreferences.setMockInitialValues({});
    AegisBridge.debugResetEngine();
    engineFlag.clear();
    AegisBridge.debugSetBlockIdnDomainsOverride = engineFlag.add;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'getVpnDiagnostics') {
        return <String, dynamic>{'sdkInt': 34};
      }
      return null;
    });
  });

  tearDown(() {
    AegisBridge.debugSetBlockIdnDomainsOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('defaults off, reaches the engine, and is saved', () async {
    final vpn = VpnProvider(enableSimulation: false);
    await vpn.ready;
    expect(vpn.blockIdnDomains, isFalse);
    expect(engineFlag, [false]);

    await vpn.setBlockIdnDomains(true);
    expect(vpn.blockIdnDomains, isTrue);
    expect(engineFlag.last, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('block_idn_domains'), isTrue);

    await vpn.setBlockIdnDomains(false);
    expect(engineFlag.last, isFalse);
    expect(prefs.getBool('block_idn_domains'), isFalse);
    vpn.dispose();
  });

  test('a saved on value is restored and pushed to the engine', () async {
    SharedPreferences.setMockInitialValues({'block_idn_domains': true});
    final vpn = VpnProvider(enableSimulation: false);
    await vpn.ready;
    expect(vpn.blockIdnDomains, isTrue);
    expect(engineFlag, [true]);
    vpn.dispose();
  });

  test('the setting travels in a backup', () async {
    SharedPreferences.setMockInitialValues({'block_idn_domains': true});
    final json = await ConfigSyncService.exportConfigToJson();
    expect(jsonDecode(json)['block_idn_domains'], isTrue);

    SharedPreferences.setMockInitialValues({});
    expect(await ConfigSyncService.importConfigFromJson(json), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('block_idn_domains'), isTrue);
  });

  test('a backup from before the setting leaves it off', () async {
    SharedPreferences.setMockInitialValues({});
    final json = await ConfigSyncService.exportConfigToJson();
    final old = jsonDecode(json) as Map<String, dynamic>
      ..remove('block_idn_domains');
    expect(
        await ConfigSyncService.importConfigFromJson(jsonEncode(old)), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('block_idn_domains'), isNull);

    final vpn = VpnProvider(enableSimulation: false);
    await vpn.ready;
    expect(vpn.blockIdnDomains, isFalse);
    vpn.dispose();
  });

  test('the log says why a look-alike domain was blocked', () {
    final item = DnsLogItem.fromEngine({
      'id': 7,
      'timestamp': 1760000000,
      'domain': 'xn--pple-43d.com',
      'blocked': true,
      'reason': 'idn',
    });
    expect(item.reasonText,
        'Blocked: international domain name (could imitate another site)');
    for (final lang in AppStrings.languages) {
      AppStrings.lang = lang;
      final text = describeReason(blocked: true, reason: 'idn');
      expect(text, isNot(AppStrings.get('reason_blocked')), reason: lang);
      expect(text, AppStrings.get('reason_idn'), reason: lang);
      for (final key in [
        'reason_idn',
        'settings_idn_title',
        'settings_idn_desc'
      ]) {
        expect(AppStrings.rawFor(lang, key), isNotNull,
            reason: '$lang is missing $key');
      }
    }
  });

  testWidgets('the settings switch turns the protection on and off',
      (tester) async {
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

    final finder = find.byKey(const Key('idn_switch'));
    await tester.scrollUntilVisible(finder, 300,
        scrollable: find.byType(Scrollable).first);
    expect(tester.widget<Switch>(finder).value, isFalse);
    expect(find.text('Block look-alike international domains'), findsOneWidget);

    await tester.tap(finder);
    await tester.pumpAndSettle();
    expect(vpn.blockIdnDomains, isTrue);
    expect(engineFlag.last, isTrue);
    expect(tester.widget<Switch>(finder).value, isTrue);

    await tester.tap(finder);
    await tester.pumpAndSettle();
    expect(vpn.blockIdnDomains, isFalse);
    expect(engineFlag.last, isFalse);
    vpn.dispose();
  });
}
