import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aegis_net/src/providers/theme_provider.dart';
import 'package:aegis_net/src/providers/vpn_provider.dart';
import 'package:aegis_net/src/screens/settings_screen.dart';

Future<VpnProvider> pumpSettings(WidgetTester tester) async {
  final vpnProvider = VpnProvider(enableSimulation: false);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: vpnProvider),
        ChangeNotifierProvider.value(value: ThemeProvider()),
      ],
      child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
    ),
  );
  await tester.pumpAndSettle();
  return vpnProvider;
}

/// The resolver field is the first one on the screen that takes a URL.
Finder resolverField() => find.byWidgetPredicate((widget) =>
    widget is TextField && widget.keyboardType == TextInputType.url);

/// The settings list builds its rows lazily, so the field does not exist until
/// it has been scrolled into view.
Future<void> showResolverField(WidgetTester tester) =>
    tester.scrollUntilVisible(resolverField(), 300,
        scrollable: find.byType(Scrollable).first);

Future<void> submit(WidgetTester tester, String text) async {
  await showResolverField(tester);
  await tester.enterText(resolverField(), text);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('submitting a DNS-over-TLS resolver makes it the upstream',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final vpn = await pumpSettings(tester);

    await submit(tester, '  tls://1.1.1.1#one.one.one.one  ');

    expect(vpn.upstreamDns, 'tls://1.1.1.1#one.one.one.one');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('upstream_dns'), 'tls://1.1.1.1#one.one.one.one');
    // The field shows what was stored, without the stray whitespace.
    expect(
      tester.widget<TextField>(resolverField()).controller?.text,
      'tls://1.1.1.1#one.one.one.one',
    );
    vpn.dispose();
  });

  testWidgets('a resolver the engine cannot use is refused and nothing changes',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final vpn = await pumpSettings(tester);
    final before = vpn.upstreamDns;

    await submit(tester, 'tls://1.1.1.1/dns-query');

    expect(vpn.upstreamDns, before);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('upstream_dns'), isNull);
    expect(find.byType(SnackBar), findsOneWidget);
    vpn.dispose();
  });

  testWidgets('a custom resolver already in effect is shown in the field',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'upstream_dns': 'tls://9.9.9.9#dns.quad9.net'});
    final vpn = VpnProvider(enableSimulation: false);
    // Let the provider read its saved settings before the screen is built.
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: vpn),
          ChangeNotifierProvider.value(value: ThemeProvider()),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
      ),
    );
    await tester.pumpAndSettle();
    await showResolverField(tester);

    expect(vpn.upstreamDns, 'tls://9.9.9.9#dns.quad9.net');
    expect(
      tester.widget<TextField>(resolverField()).controller?.text,
      'tls://9.9.9.9#dns.quad9.net',
    );
    vpn.dispose();
  });
}
