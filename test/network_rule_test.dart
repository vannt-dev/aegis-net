import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aegis_net/src/bridge/aegis_bridge.dart';
import 'package:aegis_net/src/i18n/app_strings.dart';
import 'package:aegis_net/src/providers/network_rule.dart';
import 'package:aegis_net/src/providers/theme_provider.dart';
import 'package:aegis_net/src/providers/vpn_provider.dart';
import 'package:aegis_net/src/screens/settings_screen.dart';
import 'package:aegis_net/src/services/config_sync_service.dart';

const _channel = MethodChannel('com.aegisnet/vpn');

/// Protection only on Wi-Fi, only on mobile data, or on both, with Wi-Fi
/// networks left out by name. The Android service applies the rule; these
/// tests cover the settings it reads and the location prompt.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;

  /// What the device answers about location access, before and after the
  /// prompt.
  late Map<String, dynamic> access;
  late Map<String, dynamic> accessAfterPrompt;
  String? currentSsid;
  late Map<String, dynamic> diagnostics;

  setUp(() {
    AppStrings.lang = 'en';
    SharedPreferences.setMockInitialValues({});
    AegisBridge.debugResetEngine();
    calls = [];
    access = {
      'sdkInt': 34,
      'fine': false,
      'background': false,
      'locationOn': true
    };
    accessAfterPrompt = access;
    currentSsid = null;
    diagnostics = {'sdkInt': 34};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getVpnDiagnostics':
          return diagnostics;
        case 'getLocationAccess':
          return access;
        case 'requestLocationAccess':
          access = accessAfterPrompt;
          return access;
        case 'currentWifiSsid':
          return currentSsid;
        case 'startVpn':
        case 'stopVpn':
        case 'applyNetworkRule':
          return true;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  List<String> methods() => calls.map((c) => c.method).toList();

  test('off by default: every network, no Wi-Fi list, nothing asked', () async {
    final vpn = VpnProvider(enableSimulation: false);
    await vpn.ready;
    expect(vpn.networkScope, NetworkScope.all);
    expect(vpn.ssidExceptionsOn, isFalse);
    expect(vpn.ssidExceptions, isEmpty);
    expect(vpn.networkIdle, isFalse);
    expect(methods(), isNot(contains('requestLocationAccess')));
    expect(methods(), isNot(contains('getLocationAccess')));
    vpn.dispose();
  });

  test('the choice is saved where the service reads it and handed over',
      () async {
    final vpn = VpnProvider(enableSimulation: false);
    await vpn.ready;
    calls.clear();

    await vpn.setNetworkScope(NetworkScope.wifiOnly);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('network_rule_mode'), 'wifi');
    expect(methods(), ['applyNetworkRule']);

    await vpn.setNetworkScope(NetworkScope.mobileOnly);
    expect(prefs.getString('network_rule_mode'), 'mobile');

    calls.clear();
    await vpn.setNetworkScope(NetworkScope.mobileOnly);
    expect(methods(), isEmpty, reason: 'no change, nothing to hand over');
    vpn.dispose();
  });

  test('saved settings come back after a restart', () async {
    SharedPreferences.setMockInitialValues({
      'network_rule_mode': 'mobile',
      'network_ssid_exceptions_on': true,
      'network_ssid_exceptions': 'Home\nOffice 5G\n',
    });
    final vpn = VpnProvider(enableSimulation: false);
    await vpn.ready;
    expect(vpn.networkScope, NetworkScope.mobileOnly);
    expect(vpn.ssidExceptionsOn, isTrue);
    expect(vpn.ssidExceptions, ['Home', 'Office 5G']);
    vpn.dispose();
  });

  test('a value from a newer version means every network', () {
    expect(NetworkScope.fromStored('roaming-only'), NetworkScope.all);
    expect(NetworkScope.fromStored(null), NetworkScope.all);
    expect(NetworkScope.fromStored('wifi'), NetworkScope.wifiOnly);
  });

  test('turning the Wi-Fi list on asks for location access', () async {
    accessAfterPrompt = {...access, 'fine': true};
    final vpn = VpnProvider(enableSimulation: false);
    await vpn.ready;
    calls.clear();

    final result = await vpn.setSsidExceptionsOn(true);
    expect(result.granted, isTrue);
    expect(vpn.ssidExceptionsOn, isTrue);
    expect(methods(),
        ['getLocationAccess', 'requestLocationAccess', 'applyNetworkRule']);
    expect(calls[1].arguments, {'background': false});
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('network_ssid_exceptions_on'), isTrue);
    vpn.dispose();
  });

  test('access already given is not asked for again', () async {
    access = {...access, 'fine': true};
    final vpn = VpnProvider(enableSimulation: false);
    await vpn.ready;
    calls.clear();
    await vpn.setSsidExceptionsOn(true);
    expect(methods(), isNot(contains('requestLocationAccess')));
    vpn.dispose();
  });

  test('a refusal keeps the list on, unused, and says so', () async {
    final vpn = VpnProvider(enableSimulation: false);
    await vpn.ready;
    final result = await vpn.setSsidExceptionsOn(true);
    expect(result.granted, isFalse);
    expect(vpn.ssidExceptionsOn, isTrue);
    expect(vpn.locationAccess.granted, isFalse);
    vpn.dispose();
  });

  test('turning the list off asks for nothing', () async {
    SharedPreferences.setMockInitialValues(
        {'network_ssid_exceptions_on': true});
    final vpn = VpnProvider(enableSimulation: false);
    await vpn.ready;
    calls.clear();
    await vpn.setSsidExceptionsOn(false);
    expect(methods(), ['applyNetworkRule']);
    expect(vpn.ssidExceptionsOn, isFalse);
    vpn.dispose();
  });

  test('"all the time" is offered only on Android 10+ once access is given',
      () {
    LocationAccess at(int sdk, {bool fine = true, bool background = false}) =>
        LocationAccess.fromMap({
          'sdkInt': sdk,
          'fine': fine,
          'background': background,
          'locationOn': true,
        });
    expect(at(34).needsBackground, isTrue);
    expect(at(34, background: true).needsBackground, isFalse);
    expect(at(34, fine: false).needsBackground, isFalse);
    expect(at(28).needsBackground, isFalse);
    // A build whose manifest leaves "all the time" out never offers it.
    expect(
        LocationAccess.fromMap({
          'sdkInt': 34,
          'fine': true,
          'background': false,
          'backgroundAvailable': false,
        }).needsBackground,
        isFalse);
  });

  test('Wi-Fi names are checked, kept one per line, and removed', () async {
    final vpn = VpnProvider(enableSimulation: false);
    await vpn.ready;

    expect(await vpn.addSsidException('  Home  '), isTrue);
    expect(await vpn.addSsidException(' Cafe ', exact: true), isTrue);
    expect(await vpn.addSsidException('Home'), isFalse, reason: 'listed');
    expect(await vpn.addSsidException('   '), isFalse);
    expect(await vpn.addSsidException('a\nb'), isFalse);
    expect(await vpn.addSsidException('x' * 33), isFalse);
    expect(await vpn.addSsidException('x' * 32), isTrue);
    // 12 letters of 3 bytes each is past the 32 bytes a Wi-Fi name has.
    expect(await vpn.addSsidException('ネットワークネットワーク'), isFalse);
    expect(vpn.ssidExceptions, ['Home', ' Cafe ', 'x' * 32]);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('network_ssid_exceptions'),
        'Home\n Cafe \n${'x' * 32}');

    await vpn.removeSsidException(' Cafe ');
    expect(prefs.getString('network_ssid_exceptions'), 'Home\n${'x' * 32}');
    vpn.dispose();
  });

  test('the dashboard learns when the tunnel stops filtering here', () async {
    final vpn = VpnProvider(enableSimulation: false);
    await vpn.ready;
    Future<void> report(bool idle) {
      diagnostics = {'sdkInt': 34, 'tunnelUp': true, 'networkIdle': idle};
      return vpn.onTunnelState(diagnostics);
    }

    await report(true);
    expect(vpn.isVpnActive, isTrue);
    expect(vpn.networkIdle, isTrue);

    await report(false);
    expect(vpn.networkIdle, isFalse);

    await report(true);
    await vpn.onTunnelState({'tunnelUp': false});
    expect(vpn.networkIdle, isFalse);
    vpn.dispose();
  });

  test('the settings travel in a backup, and bad values are dropped', () async {
    SharedPreferences.setMockInitialValues({
      'network_rule_mode': 'wifi',
      'network_ssid_exceptions_on': true,
      'network_ssid_exceptions': 'Home\nOffice',
    });
    final json = await ConfigSyncService.exportConfigToJson();
    final data = jsonDecode(json) as Map<String, dynamic>;
    expect(data['network_rule_mode'], 'wifi');
    expect(data['network_ssid_exceptions_on'], isTrue);
    expect(data['network_ssid_exceptions'], ['Home', 'Office']);

    SharedPreferences.setMockInitialValues({});
    expect(await ConfigSyncService.importConfigFromJson(json), isTrue);
    var prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('network_rule_mode'), 'wifi');
    expect(prefs.getBool('network_ssid_exceptions_on'), isTrue);
    expect(prefs.getString('network_ssid_exceptions'), 'Home\nOffice');

    data['network_rule_mode'] = 'nonsense';
    data['network_ssid_exceptions'] = ['Ok', 'bad\nname', 42, ''];
    SharedPreferences.setMockInitialValues({});
    expect(
        await ConfigSyncService.importConfigFromJson(jsonEncode(data)), isTrue);
    prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('network_rule_mode'), isNull);
    expect(prefs.getString('network_ssid_exceptions'), 'Ok');
  });

  test('a backup from before the setting leaves it off', () async {
    final json = await ConfigSyncService.exportConfigToJson();
    final old = jsonDecode(json) as Map<String, dynamic>
      ..remove('network_rule_mode')
      ..remove('network_ssid_exceptions_on')
      ..remove('network_ssid_exceptions');
    SharedPreferences.setMockInitialValues({});
    expect(
        await ConfigSyncService.importConfigFromJson(jsonEncode(old)), isTrue);
    final vpn = VpnProvider(enableSimulation: false);
    await vpn.ready;
    expect(vpn.networkScope, NetworkScope.all);
    expect(vpn.ssidExceptionsOn, isFalse);
    vpn.dispose();
  });

  test('every language has the strings', () {
    for (final lang in AppStrings.languages) {
      for (final key in [
        'settings_network_title',
        'settings_network_desc',
        'network_scope_all',
        'network_scope_wifi',
        'network_scope_mobile',
        'settings_ssid_title',
        'settings_ssid_desc',
        'ssid_denied',
        'ssid_background_note',
        'network_idle_title',
        'network_idle_body',
      ]) {
        expect(AppStrings.rawFor(lang, key), isNotNull,
            reason: '$lang is missing $key');
      }
    }
  });

  Future<VpnProvider> pumpSettings(WidgetTester tester) async {
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
    return vpn;
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('the card sets where protection applies', (tester) async {
    final vpn = await pumpSettings(tester);
    final wifi = find.byKey(const Key('network_scope_wifi'));
    await scrollTo(tester, wifi);
    expect(find.text('Networks to protect'), findsOneWidget);

    await tester.tap(wifi);
    await tester.pumpAndSettle();
    expect(vpn.networkScope, NetworkScope.wifiOnly);

    await tester.tap(find.byKey(const Key('network_scope_all')));
    await tester.pumpAndSettle();
    expect(vpn.networkScope, NetworkScope.all);
    vpn.dispose();
  });

  testWidgets('the Wi-Fi list asks for location and explains a refusal',
      (tester) async {
    final vpn = await pumpSettings(tester);
    final toggle = find.byKey(const Key('ssid_exceptions_switch'));
    await scrollTo(tester, toggle);
    expect(find.byKey(const Key('ssid_field')), findsNothing);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(methods(), contains('requestLocationAccess'));
    expect(vpn.ssidExceptionsOn, isTrue);
    expect(find.byKey(const Key('ssid_access_note')), findsOneWidget);
    expect(find.textContaining('Precise location access was not given'),
        findsOneWidget);

    // Granted on the second try, only while in use: "all the time" is offered.
    accessAfterPrompt = {...access, 'fine': true};
    await scrollTo(tester, find.byKey(const Key('ssid_grant')));
    await tester.tap(find.byKey(const Key('ssid_grant')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ssid_background_action')), findsOneWidget);

    calls.clear();
    accessAfterPrompt = {...access, 'background': true};
    await scrollTo(tester, find.byKey(const Key('ssid_background_action')));
    await tester.tap(find.byKey(const Key('ssid_background_action')));
    await tester.pumpAndSettle();
    expect(calls.single.arguments, {'background': true});
    expect(find.byKey(const Key('ssid_access_note')), findsNothing);
    vpn.dispose();
  });

  testWidgets('networks are added by name or from the current Wi-Fi',
      (tester) async {
    access = {...access, 'fine': true, 'background': true};
    SharedPreferences.setMockInitialValues(
        {'network_ssid_exceptions_on': true});
    final vpn = await pumpSettings(tester);

    final field = find.byKey(const Key('ssid_field'));
    await scrollTo(tester, field);
    await tester.enterText(field, 'Home');
    await scrollTo(tester, find.byKey(const Key('ssid_add')));
    await tester.tap(find.byKey(const Key('ssid_add')));
    await tester.pumpAndSettle();
    expect(vpn.ssidExceptions, ['Home']);

    final current = find.byKey(const Key('ssid_add_current'));
    await scrollTo(tester, current);
    await tester.tap(current);
    await tester.pumpAndSettle();
    expect(find.text('Could not read the name of the current Wi-Fi network.'),
        findsOneWidget);

    currentSsid = 'Office 5G';
    await tester.tap(current);
    await tester.pumpAndSettle();
    expect(vpn.ssidExceptions, ['Home', 'Office 5G']);
    expect(find.text('Office 5G'), findsOneWidget);
    vpn.dispose();
  });
}
