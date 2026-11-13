import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aegis_net/src/providers/vpn_provider.dart';

/// Pausing protection used to stop the tunnel and keep the end of the pause
/// only in a Dart timer. Android closes a backgrounded app whose tunnel is
/// down, the timer goes with it, and protection stayed off until the user
/// noticed. The tunnel now holds the pause itself and turns filtering back on
/// at the end; these tests cover the Dart half of that hand-over.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const vpnChannel = MethodChannel('com.aegisnet/vpn');
  late List<MethodCall> calls;

  /// A stand-in for MainActivity. [pauseSupported] false answers the pause
  /// calls the way a platform without them does (iOS, desktop).
  void mockTunnel({
    bool pauseSupported = true,
    Map<String, dynamic> diagnostics = const {},
  }) {
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
          return diagnostics;
      }
      return null;
    });
  }

  List<String> methods() => calls.map((c) => c.method).toList();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(vpnChannel, null);
  });

  test('pause hands its end to the running tunnel instead of stopping it',
      () async {
    mockTunnel();
    final provider = VpnProvider(enableSimulation: false);
    await provider.ready;
    await provider.toggleVpn();
    calls.clear();

    final before = DateTime.now();
    await provider.pauseProtection(const Duration(minutes: 15));

    expect(methods(), isNot(contains('stopVpn')));
    final pause = calls.singleWhere((c) => c.method == 'pauseVpn');
    final until = DateTime.fromMillisecondsSinceEpoch(
        (pause.arguments as Map)['until'] as int);
    expect(until.difference(before).inSeconds, closeTo(15 * 60, 2));
    expect(provider.isPaused, isTrue);
    expect(provider.isVpnActive, isFalse);
    provider.dispose();
  });

  test('resume asks the tunnel to filter again with the current settings',
      () async {
    mockTunnel();
    final provider = VpnProvider(enableSimulation: false);
    await provider.ready;
    provider.addBypassApp('com.example.bank');
    await provider.toggleVpn();
    await provider.pauseProtection(const Duration(minutes: 5));
    calls.clear();

    await provider.resumeProtection();

    expect(methods(), isNot(contains('startVpn')));
    final resume = calls.singleWhere((c) => c.method == 'resumeVpn');
    expect((resume.arguments as Map)['bypassApps'], ['com.example.bank']);
    expect(provider.isPaused, isFalse);
    expect(provider.isVpnActive, isTrue);
    provider.dispose();
  });

  test('without a pausing tunnel the pause stops it and starts it again',
      () async {
    mockTunnel(pauseSupported: false);
    final provider = VpnProvider(enableSimulation: false);
    await provider.ready;
    await provider.toggleVpn();
    calls.clear();

    await provider.pauseProtection(const Duration(minutes: 5));
    expect(methods(), contains('stopVpn'));
    expect(provider.isPaused, isTrue);

    calls.clear();
    await provider.resumeProtection();
    expect(methods(), contains('startVpn'));
    expect(provider.isVpnActive, isTrue);
    provider.dispose();
  });

  test('a pause that runs out asks the tunnel to filter again', () async {
    mockTunnel();
    final provider = VpnProvider(enableSimulation: false);
    await provider.ready;
    await provider.toggleVpn();
    await provider.pauseProtection(const Duration(milliseconds: 1200));
    calls.clear();

    await Future<void>.delayed(const Duration(milliseconds: 2500));

    expect(methods(), contains('resumeVpn'));
    expect(methods(), isNot(contains('startVpn')));
    expect(provider.isPaused, isFalse);
    expect(provider.isVpnActive, isTrue);
    provider.dispose();
  });

  test('a reopened app shows the pause the running tunnel is holding',
      () async {
    final until = DateTime.now().add(const Duration(minutes: 10));
    mockTunnel(diagnostics: {
      'tunnelUp': true,
      'pausedUntil': until.millisecondsSinceEpoch,
    });

    final provider = VpnProvider(enableSimulation: false);
    await provider.ready;

    expect(provider.isPaused, isTrue);
    expect(provider.isVpnActive, isFalse);
    expect(provider.pauseRemaining.inMinutes, 9);

    // Resuming from the reopened app reaches the tunnel too.
    await provider.resumeProtection();
    expect(methods(), contains('resumeVpn'));
    expect(provider.isVpnActive, isTrue);
    provider.dispose();
  });

  test('a pause that ended while the app was closed is not shown', () async {
    mockTunnel(diagnostics: {
      'tunnelUp': true,
      'pausedUntil': DateTime.now()
          .subtract(const Duration(minutes: 1))
          .millisecondsSinceEpoch,
    });

    final provider = VpnProvider(enableSimulation: false);
    await provider.ready;

    expect(provider.isPaused, isFalse);
    expect(provider.isVpnActive, isTrue);
    provider.dispose();
  });
}
