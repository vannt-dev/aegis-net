import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aegis_net/src/bridge/aegis_bridge.dart';
import 'package:aegis_net/src/i18n/app_strings.dart';
import 'package:aegis_net/src/providers/theme_provider.dart';
import 'package:aegis_net/src/providers/vpn_provider.dart';
import 'package:aegis_net/src/screens/settings_screen.dart';

const _channel = MethodChannel('com.aegisnet/vpn');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  final engineFlag = <bool>[];

  setUp(() {
    AppStrings.lang = 'en';
    SharedPreferences.setMockInitialValues({});
    AegisBridge.debugResetEngine();
    calls.clear();
    engineFlag.clear();
    AegisBridge.debugSetBlockDohHostsOverride = engineFlag.add;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'startVpn':
        case 'stopVpn':
          return true;
        case 'getVpnDiagnostics':
          return <String, dynamic>{'sdkInt': 34};
      }
      return null;
    });
  });

  tearDown(() {
    AegisBridge.debugSetBlockDohHostsOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('the switch defaults on, reaches the engine, and is saved', () async {
    final vpn = VpnProvider(enableSimulation: false);
    await pumpEventQueue();
    expect(vpn.interceptHardcodedDns, isTrue);
    expect(engineFlag, contains(true));

    await vpn.setInterceptHardcodedDns(false);
    expect(engineFlag.last, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('intercept_hardcoded_dns'), isFalse);
    vpn.dispose();
  });

  test('a saved off value is restored and pushed to the engine', () async {
    SharedPreferences.setMockInitialValues({'intercept_hardcoded_dns': false});
    final vpn = VpnProvider(enableSimulation: false);
    await pumpEventQueue();
    expect(vpn.interceptHardcodedDns, isFalse);
    expect(engineFlag.last, isFalse);
    vpn.dispose();
  });

  test('starting the VPN passes the switch to the service', () async {
    final vpn = VpnProvider(enableSimulation: false);
    await pumpEventQueue();
    await vpn.toggleVpn();
    final start = calls.lastWhere((c) => c.method == 'startVpn');
    expect((start.arguments as Map)['interceptHardcodedDns'], isTrue);
    vpn.dispose();
  });

  test('changing the switch while protected rebuilds the tunnel', () async {
    final vpn = VpnProvider(enableSimulation: false);
    await pumpEventQueue();
    await vpn.toggleVpn();
    calls.clear();

    await vpn.setInterceptHardcodedDns(false);

    expect(calls.map((c) => c.method), ['stopVpn', 'startVpn']);
    expect((calls.last.arguments as Map)['interceptHardcodedDns'], isFalse);
    expect(vpn.isVpnActive, isTrue);
    vpn.dispose();
  });

  test('flipping the switch twice in a row leaves the tunnel on the last value',
      () async {
    // Like the service: a start while a tunnel is up changes nothing.
    bool? tunnelIntercepts;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      switch (call.method) {
        case 'startVpn':
          tunnelIntercepts ??=
              (call.arguments as Map)['interceptHardcodedDns'] as bool;
          return true;
        case 'stopVpn':
          tunnelIntercepts = null;
          return true;
        case 'getVpnDiagnostics':
          return <String, dynamic>{'sdkInt': 34};
      }
      return null;
    });
    final vpn = VpnProvider(enableSimulation: false);
    await pumpEventQueue();
    await vpn.toggleVpn();

    final first = vpn.setInterceptHardcodedDns(false);
    final second = vpn.setInterceptHardcodedDns(true);
    await Future.wait([first, second]);

    expect(vpn.interceptHardcodedDns, isTrue);
    expect(tunnelIntercepts, isTrue);
    vpn.dispose();
  });

  test('changing the switch with the VPN off or paused starts nothing',
      () async {
    final vpn = VpnProvider(enableSimulation: false);
    await pumpEventQueue();
    await vpn.setInterceptHardcodedDns(false);
    expect(calls.where((c) => c.method == 'startVpn'), isEmpty);

    await vpn.toggleVpn();
    await vpn.pauseProtection(const Duration(minutes: 5));
    calls.clear();
    await vpn.setInterceptHardcodedDns(true);
    expect(calls.where((c) => c.method == 'startVpn'), isEmpty);
    await vpn.resumeProtection();
    vpn.dispose();
  });

  testWidgets('Settings shows the switch and flips it', (tester) async {
    final vpn = VpnProvider(enableSimulation: false);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: vpn),
        ChangeNotifierProvider.value(value: ThemeProvider()),
      ],
      child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
    ));
    await tester.pumpAndSettle();
    final switchFinder = find.byKey(const Key('intercept_switch'));
    await tester.scrollUntilVisible(switchFinder, 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Stop apps from bypassing the filter'), findsOneWidget);
    expect(find.textContaining('pings 8.8.8.8'), findsOneWidget);

    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    expect(vpn.interceptHardcodedDns, isFalse);
    vpn.dispose();
  });

  testWidgets('off Android the description speaks only of names',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final vpn = VpnProvider(enableSimulation: false);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: vpn),
        ChangeNotifierProvider.value(value: ThemeProvider()),
      ],
      child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const Key('intercept_switch')), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('by name'), findsOneWidget);
    expect(find.textContaining('pings 8.8.8.8'), findsNothing);
    vpn.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  test('saved upstream and categories reach the engine after it starts',
      () async {
    // Pushed while the preferences loaded, they were dropped: the native
    // library was not open yet, so a restart ran on the engine's defaults.
    SharedPreferences.setMockInitialValues({
      'upstream_dns': 'tls://9.9.9.9#dns.quad9.net',
      'block_ads': false,
      'block_adult': true,
    });
    final upstreams = <String>[];
    final categories = <int, bool>{};
    AegisBridge.debugSetUpstreamDnsOverride = (upstream) {
      if (AegisBridge.debugEngineInitialized) upstreams.add(upstream);
    };
    AegisBridge.debugSetCategoryOverride = (id, enabled) {
      if (AegisBridge.debugEngineInitialized) categories[id] = enabled;
    };
    addTearDown(() {
      AegisBridge.debugSetUpstreamDnsOverride = null;
      AegisBridge.debugSetCategoryOverride = null;
    });

    final vpn = VpnProvider(enableSimulation: false);
    await vpn.ready;

    expect(upstreams, ['tls://9.9.9.9#dns.quad9.net']);
    expect(categories, {0: false, 1: true, 2: true, 3: true});
    vpn.dispose();
  });

  test('the flag reaches the engine after it is initialised', () async {
    // Calls made before initEngine never reach the native library.
    final readyAtCall = <bool>[];
    AegisBridge.debugSetBlockDohHostsOverride =
        (_) => readyAtCall.add(AegisBridge.debugEngineInitialized);
    final vpn = VpnProvider(enableSimulation: false);
    await pumpEventQueue();
    expect(readyAtCall, isNotEmpty);
    expect(readyAtCall.last, isTrue);
    vpn.dispose();
  });
}
