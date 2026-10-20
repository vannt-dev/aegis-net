import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aegis_net/src/bridge/aegis_bridge.dart';
import 'package:aegis_net/src/i18n/app_strings.dart';
import 'package:aegis_net/src/providers/block_reason.dart';
import 'package:aegis_net/src/providers/theme_provider.dart';
import 'package:aegis_net/src/providers/vpn_provider.dart';
import 'package:aegis_net/src/screens/logs_screen.dart';

Future<VpnProvider> pumpLogs(WidgetTester tester, List<DnsLogItem> logs) async {
  SharedPreferences.setMockInitialValues({});
  final vpn = VpnProvider(enableSimulation: false);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: vpn),
        ChangeNotifierProvider.value(value: ThemeProvider()),
      ],
      child: const MaterialApp(home: LogsScreen()),
    ),
  );
  vpn.debugSetLogs(logs);
  await tester.pumpAndSettle();
  return vpn;
}

DnsLogItem entry(String domain,
        {bool blocked = true, String? reason, String? list}) =>
    DnsLogItem(
      id: domain,
      domain: domain,
      isBlocked: blocked,
      timestamp: DateTime(2026, 10, 20, 9),
      reason: reason,
      list: list,
    );

void main() {
  setUp(() => AppStrings.lang = 'en');
  tearDown(() => AegisBridge.debugExplainDomainOverride = null);

  group('describeReason', () {
    test('a category block names the list behind it', () {
      expect(
        describeReason(blocked: true, reason: 'ads', list: 'adguard_dns'),
        'Blocked by the Ads filter · AdGuard DNS Filter',
      );
      expect(
        describeReason(blocked: true, reason: 'trackers'),
        'Blocked by the Trackers filter · built-in list',
      );
    });

    test('a list the app no longer knows is shown by its id', () {
      expect(
        describeReason(blocked: true, reason: 'malware', list: 'gone_list'),
        'Blocked by the Malware filter · gone_list',
      );
    });

    test('every other reason has its own sentence', () {
      expect(describeReason(blocked: true, reason: 'custom_rule'),
          'Blocked by your block list');
      expect(describeReason(blocked: true, reason: 'app'),
          'This app is blocked from looking anything up');
      expect(describeReason(blocked: true, reason: 'bypass'),
          contains('get around the filter'));
      expect(describeReason(blocked: false, reason: 'safesearch'),
          contains('SafeSearch'));
      expect(describeReason(blocked: false, reason: 'custom_host'),
          'Answered by your custom host mapping');
      expect(describeReason(blocked: false, reason: 'allowlist'),
          'Allowed by your allow list');
      expect(
        describeReason(
            blocked: false, reason: 'exception', list: 'adguard_dns'),
        'Allowed by an exception in a filter list · AdGuard DNS Filter',
      );
    });

    test('no reason, or one this version does not know, still reads', () {
      // An engine from before reasons, or a newer one with a reason this
      // build has no sentence for.
      expect(describeReason(blocked: true), 'Blocked by your filters');
      expect(describeReason(blocked: true, reason: 'from_the_future'),
          'Blocked by your filters');
      expect(describeReason(blocked: false), 'Not on any block list');
    });

    test('every reason sentence exists in every language', () {
      for (final lang in AppStrings.languages) {
        for (final key in AppStrings.keys.where(
            (k) => k.startsWith('reason_') || k.startsWith('test_domain_'))) {
          expect(AppStrings.rawFor(lang, key), isNotNull,
              reason: '$lang is missing $key');
        }
      }
    });
  });

  group('engine JSON', () {
    test('a log entry keeps its reason and list', () {
      final item = DnsLogItem.fromEngine({
        'id': 7,
        'timestamp': 1760000000,
        'domain': 'ads.example.com',
        'blocked': true,
        'uid': 10123,
        'reason': 'ads',
        'list': 'oisd_small',
      });
      expect(item.reason, 'ads');
      expect(item.list, 'oisd_small');
      expect(item.reasonText, 'Blocked by the Ads filter · OISD Small');
    });

    test('a log entry from an older engine has no reason', () {
      final item = DnsLogItem.fromEngine({
        'id': 8,
        'timestamp': 1760000000,
        'domain': 'cdn.example.com',
        'blocked': false,
      });
      expect(item.reason, isNull);
      expect(item.list, isNull);
      expect(item.uid, -1);
    });

    test('a verdict parses', () {
      final verdict = DomainVerdict.fromJson({
        'domain': 'x.example',
        'blocked': true,
        'reason': 'custom_rule',
      });
      expect(verdict.blocked, isTrue);
      expect(verdict.describe(), 'Blocked by your block list');
    });
  });

  group('normalizeDomainInput', () {
    test('strips what people paste around a domain', () {
      expect(normalizeDomainInput(' https://Ads.Example.com/path?q=1 '),
          'ads.example.com');
      expect(normalizeDomainInput('example.com.'), 'example.com');
      expect(normalizeDomainInput('example.com:443'), 'example.com');
      expect(normalizeDomainInput('*.tracker.example'), 'tracker.example');
      expect(normalizeDomainInput('zip'), 'zip');
    });

    test('refuses what is not a domain', () {
      expect(normalizeDomainInput(''), isNull);
      expect(normalizeDomainInput('not a domain'), isNull);
      expect(normalizeDomainInput('a..b'), isNull);
      expect(normalizeDomainInput('-bad.example'), isNull);
    });
  });

  group('log sheet', () {
    testWidgets('a blocked entry says what blocked it', (tester) async {
      final vpn = await pumpLogs(tester, [
        entry('ads.example.com', reason: 'ads', list: 'adguard_dns'),
      ]);

      await tester.tap(find.text('ads.example.com'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('log-actions-reason')))
            .data,
        'Blocked by the Ads filter · AdGuard DNS Filter',
      );
      // And it can be allowed from right there.
      await tester.tap(find.byKey(const ValueKey('log-action-allow')));
      await tester.pumpAndSettle();
      expect(vpn.whitelist, ['ads.example.com']);
      vpn.dispose();
    });

    testWidgets('a plain allowed entry shows no reason line', (tester) async {
      final vpn = await pumpLogs(tester, [
        entry('cdn.example.org', blocked: false),
      ]);

      await tester.tap(find.text('cdn.example.org'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('log-actions-reason')), findsNothing);
      vpn.dispose();
    });

    testWidgets('an entry allowed by a rule says so', (tester) async {
      final vpn = await pumpLogs(tester, [
        entry('safe.example.org', blocked: false, reason: 'allowlist'),
      ]);

      await tester.tap(find.text('safe.example.org'));
      await tester.pumpAndSettle();

      expect(find.text('Allowed by your allow list'), findsOneWidget);
      vpn.dispose();
    });
  });

  group('test a domain', () {
    testWidgets('says whether a domain would be blocked and why',
        (tester) async {
      final asked = <String>[];
      late VpnProvider vpn;
      AegisBridge.debugExplainDomainOverride = (domain) {
        asked.add(domain);
        final allowed = vpn.whitelist.contains(domain);
        return DomainVerdict(
          domain: domain,
          blocked: !allowed,
          reason: allowed ? 'allowlist' : 'trackers',
          list: allowed ? null : 'pgl_yoyo',
        );
      };
      vpn = await pumpLogs(tester, []);

      await tester.tap(find.byKey(const Key('logs_test_domain')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('test-domain-input')),
          'https://Track.Example.com/pixel');
      await tester.tap(find.byKey(const ValueKey('test-domain-run')));
      await tester.pumpAndSettle();

      expect(asked, ['track.example.com']);
      expect(find.text('Would be blocked'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('test-domain-reason')))
            .data,
        startsWith('Blocked by the Trackers filter · '),
      );

      // One tap allows it, and the answer updates.
      await tester.tap(find.byKey(const ValueKey('test-domain-allow')));
      await tester.pumpAndSettle();
      expect(vpn.whitelist, ['track.example.com']);
      expect(find.text('Would not be blocked'), findsOneWidget);
      expect(find.text('Allowed by your allow list'), findsOneWidget);
      expect(find.byKey(const ValueKey('test-domain-allow')), findsNothing);
      vpn.dispose();
    });

    testWidgets('refuses input that is not a domain', (tester) async {
      var calls = 0;
      AegisBridge.debugExplainDomainOverride = (domain) {
        calls++;
        return DomainVerdict(domain: domain, blocked: false);
      };
      final vpn = await pumpLogs(tester, []);

      await tester.tap(find.byKey(const Key('logs_test_domain')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('test-domain-input')), 'not a domain');
      await tester.tap(find.byKey(const ValueKey('test-domain-run')));
      await tester.pumpAndSettle();

      expect(calls, 0);
      expect(
          find.text('Enter a domain name, like example.com'), findsOneWidget);
      vpn.dispose();
    });
  });
}
