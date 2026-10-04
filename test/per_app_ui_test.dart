import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aegis_net/src/i18n/app_strings.dart';
import 'package:aegis_net/src/providers/app_info.dart';
import 'package:aegis_net/src/providers/theme_provider.dart';
import 'package:aegis_net/src/providers/vpn_provider.dart';
import 'package:aegis_net/src/screens/analytics_screen.dart';
import 'package:aegis_net/src/screens/logs_screen.dart';

final _created = <VpnProvider>[];

/// The provider starts timers, and the test binding fails on any still
/// pending when the body ends — before tear-downs run — so dispose in the body.
void perAppTest(String name, Future<void> Function(WidgetTester tester) body) {
  testWidgets(name, (tester) async {
    try {
      await body(tester);
    } finally {
      for (final vpn in _created) {
        vpn.dispose();
      }
      _created.clear();
    }
  });
}

Future<VpnProvider> pump(WidgetTester tester, Widget screen,
    {int sdk = 34}) async {
  AppStrings.lang = 'en';
  SharedPreferences.setMockInitialValues({});
  final vpn = VpnProvider(enableSimulation: false);
  _created.add(vpn);
  vpn.debugSetAndroidSdk(sdk);
  vpn.debugSetAppInfo({
    10123: const AppInfo(uid: 10123, label: 'Chrome'),
    10456: const AppInfo(uid: 10456, label: 'Maps'),
  });
  vpn.debugSetStats({
    'top_apps': [
      {'uid': 10123, 'total': 8, 'blocked': 2},
      {'uid': -1, 'total': 3, 'blocked': 0},
    ],
  });
  vpn.debugSetLogs([
    DnsLogItem(
        id: '1',
        domain: 'ads.example.com',
        isBlocked: true,
        timestamp: DateTime(2026, 10, 4, 9),
        uid: 10123),
    DnsLogItem(
        id: '2',
        domain: 'maps.example.com',
        isBlocked: false,
        timestamp: DateTime(2026, 10, 4, 9, 1),
        uid: 10456),
    DnsLogItem(
        id: '3',
        domain: 'cdn.example.com',
        isBlocked: false,
        timestamp: DateTime(2026, 10, 4, 9, 2),
        uid: 10123),
  ]);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: vpn),
      ChangeNotifierProvider.value(value: ThemeProvider()),
    ],
    child: MaterialApp(home: screen),
  ));
  await tester.pumpAndSettle();
  return vpn;
}

void main() {
  perAppTest('Analytics lists the top apps with their counts', (tester) async {
    await pump(tester, const AnalyticsScreen());
    await tester.scrollUntilVisible(
        find.byKey(const Key('top_apps_card')), 200);
    expect(find.text('Chrome'), findsOneWidget);
    expect(find.text('8 queries · 2 blocked'), findsOneWidget);
    expect(find.text('Unknown app'), findsOneWidget);
  });

  perAppTest('tapping an app filters the log to it and asks to show the log',
      (tester) async {
    int? shown;
    final vpn = await pump(
        tester, AnalyticsScreen(onShowAppLogs: (uid) => shown = uid));
    await tester.scrollUntilVisible(
        find.byKey(const Key('top_app_10123')), 200);
    await tester.tap(find.byKey(const Key('top_app_10123')));
    await tester.pumpAndSettle();
    expect(vpn.logAppFilter, 10123);
    expect(shown, 10123);
  });

  perAppTest('below Android 10 the card explains why there is nothing',
      (tester) async {
    await pump(tester, const AnalyticsScreen(), sdk: 28);
    await tester.scrollUntilVisible(
        find.byKey(const Key('top_apps_card')), 200);
    expect(find.text('Needs Android 10 or later to tell apps apart'),
        findsOneWidget);
    expect(find.text('Chrome'), findsNothing);
  });

  perAppTest('no per-app UI without Android', (tester) async {
    await pump(tester, const AnalyticsScreen(), sdk: 0);
    expect(find.byKey(const Key('top_apps_card')), findsNothing);
    await pump(tester, const LogsScreen(), sdk: 0);
    expect(find.byKey(const Key('logs_app_filter')), findsNothing);
    expect(find.textContaining('Chrome'), findsNothing);
  });

  perAppTest('log lines name their app', (tester) async {
    await pump(tester, const LogsScreen());
    expect(find.text('09:00:00 · Chrome'), findsOneWidget);
    expect(find.text('09:01:00 · Maps'), findsOneWidget);
  });

  perAppTest('the app filter combines with search and status, and clears',
      (tester) async {
    final vpn = await pump(tester, const LogsScreen());
    await tester.tap(find.byKey(const Key('logs_app_filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logs_app_option_10123')));
    await tester.pumpAndSettle();

    expect(vpn.logAppFilter, 10123);
    expect(find.text('ads.example.com'), findsOneWidget);
    expect(find.text('cdn.example.com'), findsOneWidget);
    expect(find.text('maps.example.com'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'cdn');
    await tester.pumpAndSettle();
    expect(find.text('ads.example.com'), findsNothing);
    expect(find.text('cdn.example.com'), findsOneWidget);

    await tester.tap(find.descendant(
        of: find.byKey(const Key('logs_app_chip')),
        matching: find.byIcon(Icons.cancel)));
    await tester.pumpAndSettle();
    expect(vpn.logAppFilter, isNull);
  });

  perAppTest('filter chip clears an app no longer in the log', (tester) async {
    final vpn = await pump(tester, const LogsScreen());
    vpn.setLogAppFilter(99999);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('logs_app_chip')), findsOneWidget);
    expect(find.text('ads.example.com'), findsNothing);
    await tester.tap(find.descendant(
        of: find.byKey(const Key('logs_app_chip')),
        matching: find.byIcon(Icons.cancel)));
    await tester.pumpAndSettle();
    expect(find.text('ads.example.com'), findsOneWidget);
  });

  test('CSV export has an App column and quotes names with commas', () {
    final csv = logsToCsv([
      DnsLogItem(
          id: '1',
          domain: 'a.example',
          isBlocked: true,
          timestamp: DateTime.utc(2026, 10, 4),
          uid: 10123),
    ], (uid) => 'Maps, Google');
    final lines = csv.trim().split('\n');
    expect(lines.first, 'ID,Timestamp,Domain,Status,App');
    expect(lines[1], endsWith(',BLOCKED,"Maps, Google"'));
  });

  perAppTest('below Android 10 the log has no app filter', (tester) async {
    await pump(tester, const LogsScreen(), sdk: 28);
    expect(find.byKey(const Key('logs_app_filter')), findsNothing);
  });
}
