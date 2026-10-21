import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aegis_net/src/bridge/aegis_bridge.dart';
import 'package:aegis_net/src/i18n/app_strings.dart';
import 'package:aegis_net/src/providers/daily_history.dart';
import 'package:aegis_net/src/providers/theme_provider.dart';
import 'package:aegis_net/src/providers/vpn_provider.dart';
import 'package:aegis_net/src/screens/analytics_screen.dart';

/// The engine numbers days from 1970-01-01.
int dayNumber(DateTime date) => DateTime.utc(date.year, date.month, date.day)
    .difference(DateTime.utc(1970))
    .inDays;

DateTime today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

String dayKey(DateTime date) =>
    'history_day_${DateFormat('yyyy-MM-dd').format(date)}';

void main() {
  group('DayStat from the engine', () {
    test('reads a day with its counts and top blocked domains', () {
      final day = DayStat.fromEngine({
        'day': dayNumber(DateTime(2026, 10, 20)),
        'total': 12,
        'blocked': 5,
        'top_blocked': [
          {'domain': 'ads.example', 'count': 4},
          {'domain': 'track.example', 'count': 1},
        ],
      })!;
      expect(day.date, DateTime(2026, 10, 20));
      expect(day.total, 12);
      expect(day.blocked, 5);
      expect(day.allowed, 7);
      expect(
          day.topBlocked.map((e) => e.key), ['ads.example', 'track.example']);
      expect(day.topBlocked.first.value, 4);
    });

    test('skips elements that do not parse and sorts newest first', () {
      final days = DayStat.listFromEngine([
        {'day': dayNumber(DateTime(2026, 10, 18)), 'total': 1, 'blocked': 0},
        'garbage',
        {'total': 3},
        {'day': dayNumber(DateTime(2026, 10, 20)), 'total': 2, 'blocked': 1},
      ]);
      expect(days.map((d) => d.date),
          [DateTime(2026, 10, 20), DateTime(2026, 10, 18)]);
      expect(DayStat.listFromEngine({'not': 'a list'}), isEmpty);
      expect(DayStat.listFromEngine(null), isEmpty);
    });

    test('a missing domain list is an empty one', () {
      final day = DayStat.fromEngine(
          {'day': dayNumber(DateTime(2026, 1, 1)), 'total': 4, 'blocked': 0})!;
      expect(day.topBlocked, isEmpty);
    });

    test('days without traffic are filled in for the chart', () {
      final filled = DayStat.withGapsFilled([
        DayStat(date: DateTime(2026, 10, 21), total: 5, blocked: 2),
        DayStat(date: DateTime(2026, 10, 18), total: 3, blocked: 1),
      ]);
      expect(filled.map((d) => d.date.day), [18, 19, 20, 21]);
      expect(filled.map((d) => d.total), [3, 0, 0, 5]);
      expect(DayStat.withGapsFilled(const []), isEmpty);
    });

    test('filling gaps crosses a month end', () {
      final filled = DayStat.withGapsFilled([
        DayStat(date: DateTime(2026, 11, 1), total: 1, blocked: 0),
        DayStat(date: DateTime(2026, 10, 30), total: 1, blocked: 0),
      ]);
      expect(filled.map((d) => d.date), [
        DateTime(2026, 10, 30),
        DateTime(2026, 10, 31),
        DateTime(2026, 11, 1)
      ]);
    });
  });

  group('History on the Analytics screen', () {
    tearDown(() => AegisBridge.debugDailyHistoryOverride = null);

    Future<VpnProvider> pump(WidgetTester tester) async {
      AppStrings.lang = 'en';
      SharedPreferences.setMockInitialValues({});
      final vpn = VpnProvider(enableSimulation: false);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: vpn),
          ChangeNotifierProvider.value(value: ThemeProvider()),
        ],
        child: const MaterialApp(home: AnalyticsScreen()),
      ));
      await tester.pumpAndSettle();
      return vpn;
    }

    testWidgets('says nothing is recorded yet when there is no history',
        (tester) async {
      AegisBridge.debugDailyHistoryOverride = () => const [];
      final vpn = await pump(tester);
      try {
        await tester.scrollUntilVisible(
            find.byKey(const Key('daily_history_empty')), 300);
        expect(find.text(AppStrings.get('history_title')), findsOneWidget);
        expect(vpn.dailyHistory, isEmpty);
      } finally {
        vpn.dispose();
      }
    });

    testWidgets('lists each day with its counts and most blocked domains',
        (tester) async {
      final yesterday = today().subtract(const Duration(days: 1));
      AegisBridge.debugDailyHistoryOverride = () => [
            DayStat(
              date: today(),
              total: 40,
              blocked: 9,
              topBlocked: const [
                MapEntry('ads.example', 6),
                MapEntry('track.example', 3),
              ],
            ),
            DayStat(date: yesterday, total: 120, blocked: 30),
          ];
      final vpn = await pump(tester);
      try {
        expect(vpn.dailyHistory, hasLength(2));
        await tester.scrollUntilVisible(
            find.byKey(Key(dayKey(yesterday))), 300);
        final todayRow = find.byKey(Key(dayKey(today())));
        expect(todayRow, findsOneWidget);
        expect(
            find.descendant(
                of: todayRow,
                matching: find.text(AppStrings.get('history_today'))),
            findsOneWidget);
        expect(
            find.descendant(
                of: todayRow, matching: find.text('40 queries · 9 blocked')),
            findsOneWidget);
        expect(
            find.descendant(
                of: todayRow,
                matching:
                    find.text('Most blocked: ads.example, track.example')),
            findsOneWidget);
        expect(find.text('120 queries · 30 blocked'), findsOneWidget);
        expect(find.byKey(const Key('daily_history_empty')), findsNothing);
      } finally {
        vpn.dispose();
      }
    });

    testWidgets('shows a new day after the history is read again',
        (tester) async {
      var days = <DayStat>[];
      AegisBridge.debugDailyHistoryOverride = () => days;
      final vpn = await pump(tester);
      try {
        await tester.scrollUntilVisible(
            find.byKey(const Key('daily_history_empty')), 300);
        days = [DayStat(date: today(), total: 7, blocked: 2)];
        vpn.refreshHistory();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('daily_history_empty')), findsNothing);
        expect(find.byKey(Key(dayKey(today()))), findsOneWidget);
      } finally {
        vpn.dispose();
      }
    });
  });
}
