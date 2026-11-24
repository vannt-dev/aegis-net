import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aegis_net/src/providers/vpn_provider.dart';

/// The notification's Pause and Resume buttons and the home-screen widget
/// change the tunnel behind the screen's back. The tunnel then reports what
/// it did (`tunnelStateChanged`), and the screen follows instead of showing
/// what it last did itself.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const vpnChannel = MethodChannel('com.aegisnet/vpn');
  late List<MethodCall> calls;

  void mockTunnel({bool pauseSupported = true}) {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(vpnChannel, (MethodCall call) async {
      calls.add(call);
      switch (call.method) {
        case 'startVpn':
        case 'stopVpn':
          return true;
        case 'pauseVpn':
        case 'resumeVpn':
          if (!pauseSupported) throw MissingPluginException();
          return true;
        case 'getVpnDiagnostics':
          return <String, dynamic>{};
      }
      return null;
    });
  }

  /// What MainActivity sends when the tunnel changes state.
  Future<void> tunnelReports(Map<String, dynamic> diagnostics) async {
    const codec = StandardMethodCodec();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      vpnChannel.name,
      codec.encodeMethodCall(MethodCall('tunnelStateChanged', diagnostics)),
      (_) {},
    );
    await pumpEventQueue();
  }

  List<String> methods() => calls.map((c) => c.method).toList();

  Future<VpnProvider> protectedProvider() async {
    final provider = VpnProvider(enableSimulation: false);
    await provider.ready;
    await provider.toggleVpn();
    calls.clear();
    return provider;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockTunnel();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(vpnChannel, null);
  });

  test('a pause from the notification shows with its time left', () async {
    final provider = await protectedProvider();
    final until = DateTime.now().add(const Duration(minutes: 5));

    await tunnelReports(
        {'tunnelUp': true, 'pausedUntil': until.millisecondsSinceEpoch});

    expect(provider.isPaused, isTrue);
    expect(provider.isVpnActive, isFalse);
    expect(provider.pauseRemaining.inSeconds, closeTo(5 * 60, 2));
    // The tunnel already holds the pause; nothing is sent back.
    expect(methods(), isEmpty);
    provider.dispose();
  });

  test('a resume from the notification hands over settings held back',
      () async {
    final provider = await protectedProvider();
    await provider.pauseProtection(const Duration(minutes: 5));
    provider.addBypassApp('com.example.bank');
    calls.clear();

    await tunnelReports({'tunnelUp': true, 'pausedUntil': 0});

    expect(provider.isPaused, isFalse);
    expect(provider.isVpnActive, isTrue);
    final resume = calls.singleWhere((c) => c.method == 'resumeVpn');
    expect((resume.arguments as Map)['bypassApps'], ['com.example.bank']);
    provider.dispose();
  });

  test("the screen's own pause reported back changes nothing", () async {
    final provider = await protectedProvider();
    await provider.pauseProtection(const Duration(minutes: 15));
    final pause = calls.singleWhere((c) => c.method == 'pauseVpn');
    calls.clear();

    await tunnelReports({
      'tunnelUp': true,
      'pausedUntil': (pause.arguments as Map)['until'],
    });

    expect(methods(), isEmpty);
    expect(provider.isPaused, isTrue);
    provider.dispose();
  });

  test('turned off from the widget, the screen shows it off', () async {
    final provider = await protectedProvider();

    await tunnelReports({'tunnelUp': false, 'pausedUntil': 0});

    expect(provider.isVpnActive, isFalse);
    expect(provider.isPaused, isFalse);
    expect(methods(), isEmpty);
    provider.dispose();
  });

  test('turned on from the widget, the screen shows it on', () async {
    final provider = VpnProvider(enableSimulation: false);
    await provider.ready;
    calls.clear();

    await tunnelReports({'tunnelUp': true, 'pausedUntil': 0});

    expect(provider.isVpnActive, isTrue);
    expect(methods(), isNot(contains('startVpn')));
    provider.dispose();
  });

  test('a pause that stopped the tunnel on purpose is not a tunnel lost',
      () async {
    mockTunnel(pauseSupported: false);
    final provider = await protectedProvider();
    await provider.pauseProtection(const Duration(minutes: 5));

    await tunnelReports({'tunnelUp': false, 'pausedUntil': 0});

    expect(provider.isPaused, isTrue);
    provider.dispose();
  });

  test('a pause held by the tunnel ends when the tunnel goes down', () async {
    final provider = await protectedProvider();
    await provider.pauseProtection(const Duration(minutes: 5));

    // The tile turned protection off in the middle of the pause.
    await tunnelReports({'tunnelUp': false, 'pausedUntil': 0});

    expect(provider.isPaused, isFalse);
    expect(provider.isVpnActive, isFalse);
    provider.dispose();
  });

  test('the widget is handed the local day the history counts in', () {
    expect(VpnProvider.localDayNumber(DateTime(1970, 1, 1, 23, 59)), 0);
    expect(VpnProvider.localDayNumber(DateTime(1970, 1, 2, 0, 1)), 1);
    expect(VpnProvider.localDayNumber(DateTime(2026, 11, 24, 12)), 20781);
  });
}
