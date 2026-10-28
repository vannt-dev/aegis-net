import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aegis_net/src/i18n/app_strings.dart';
import 'package:aegis_net/src/providers/theme_provider.dart';
import 'package:aegis_net/src/providers/vpn_provider.dart';
import 'package:aegis_net/src/screens/logs_screen.dart';

Future<VpnProvider> pumpLogs(WidgetTester tester) async {
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
  vpn.debugSetLogs([
    DnsLogItem(
      id: '1',
      domain: 'ads.Example.com',
      isBlocked: true,
      timestamp: DateTime(2026, 10, 2, 9, 0),
    ),
    DnsLogItem(
      id: '2',
      domain: 'cdn.example.org',
      isBlocked: false,
      timestamp: DateTime(2026, 10, 2, 9, 1),
    ),
  ]);
  await tester.pumpAndSettle();
  return vpn;
}

Future<void> openActions(WidgetTester tester, String domain) async {
  await tester.tap(find.text(domain));
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => AppStrings.lang = 'en');

  testWidgets('a blocked domain can be allowed from the log', (tester) async {
    final vpn = await pumpLogs(tester);
    vpn.addBlacklistDomain('ads.example.com');

    await openActions(tester, 'ads.Example.com');
    // The sheet shows the name the rule will be stored under.
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('log-actions-domain')))
          .data,
      'ads.example.com',
    );
    expect(find.text('Remove from the block list'), findsOneWidget);
    await choose(tester, 'log-action-allow');

    expect(vpn.whitelist, ['ads.example.com']);
    expect(vpn.blacklist, isEmpty, reason: 'one name, one list');
    expect(find.text('ads.example.com is now always allowed.'), findsOneWidget);
    expect(find.byKey(const ValueKey('log-actions-domain')), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('whitelist'), ['ads.example.com']);
    expect(prefs.getStringList('blacklist'), isEmpty);
    vpn.dispose();
  });

  testWidgets('an allowed domain can be blocked from the log', (tester) async {
    final vpn = await pumpLogs(tester);
    vpn.addWhitelistDomain('cdn.example.org');

    await openActions(tester, 'cdn.example.org');
    await choose(tester, 'log-action-block');

    expect(vpn.blacklist, ['cdn.example.org']);
    expect(vpn.whitelist, isEmpty);
    expect(find.text('cdn.example.org is now always blocked.'), findsOneWidget);
    vpn.dispose();
  });

  testWidgets('a domain already on a list offers to take it off',
      (tester) async {
    final vpn = await pumpLogs(tester);
    vpn.allowDomain('cdn.example.org');

    await openActions(tester, 'cdn.example.org');
    expect(find.text('Remove from the allow list'), findsOneWidget);
    expect(find.text('Always block this domain'), findsOneWidget);
    await choose(tester, 'log-action-allow');

    expect(vpn.whitelist, isEmpty);
    expect(vpn.blacklist, isEmpty);
    expect(find.text('Removed the rule for cdn.example.org.'), findsOneWidget);
    vpn.dispose();
  });

  testWidgets('a blocked domain can be allowed for an hour, then stopped',
      (tester) async {
    final vpn = await pumpLogs(tester);

    await openActions(tester, 'ads.Example.com');
    await choose(tester, 'log-action-allow-1h');

    final until = vpn.temporaryAllowUntil('ads.example.com');
    expect(until, isNotNull);
    expect(
        until!.difference(DateTime.now()).inMinutes, inInclusiveRange(58, 60));
    expect(vpn.whitelist, isEmpty, reason: 'never on the permanent list');
    expect(find.textContaining('ads.example.com is allowed until'),
        findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('temporary_allows'),
        ['ads.example.com=${until.millisecondsSinceEpoch ~/ 1000}']);
    expect(prefs.getStringList('whitelist'), isNull);

    await openActions(tester, 'ads.Example.com');
    expect(find.byKey(const ValueKey('log-action-allow-1h')), findsNothing);
    await choose(tester, 'log-action-stop-timed');

    expect(vpn.temporaryAllowUntil('ads.example.com'), isNull);
    expect(find.text('ads.example.com is blocked again.'), findsOneWidget);
    expect(prefs.getStringList('temporary_allows'), isEmpty);
    vpn.dispose();
  });

  testWidgets('a permanently allowed domain offers no timed allow',
      (tester) async {
    final vpn = await pumpLogs(tester);
    vpn.allowDomain('cdn.example.org');

    await openActions(tester, 'cdn.example.org');
    expect(find.byKey(const ValueKey('log-action-allow-15m')), findsNothing);
    vpn.dispose();
  });

  test('saved timed allows come back unless they ran out', () async {
    final soon = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 600;
    SharedPreferences.setMockInitialValues({
      'temporary_allows': ['live.example=$soon', 'old.example=1', 'junk'],
    });
    final vpn = VpnProvider(enableSimulation: false);
    await vpn.reloadFromPreferences();

    expect(vpn.temporaryAllowUntil('live.example'),
        DateTime.fromMillisecondsSinceEpoch(soon * 1000));
    expect(vpn.temporaryAllowUntil('old.example'), isNull);
    vpn.dispose();
  });

  test('blocking a domain ends its timed allow', () async {
    SharedPreferences.setMockInitialValues({});
    final vpn = VpnProvider(enableSimulation: false);
    vpn.allowDomainFor('tracker.example', const Duration(minutes: 15));
    expect(vpn.temporaryAllowUntil('tracker.example'), isNotNull);

    vpn.blockDomain('tracker.example');
    expect(vpn.temporaryAllowUntil('tracker.example'), isNull);
    expect(vpn.blacklist, ['tracker.example']);
    vpn.dispose();
  });

  testWidgets('the domain can be copied', (tester) async {
    final vpn = await pumpLogs(tester);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );

    await openActions(tester, 'cdn.example.org');
    await choose(tester, 'log-action-copy');

    expect(copied, 'cdn.example.org');
    expect(vpn.whitelist, isEmpty);
    expect(vpn.blacklist, isEmpty);
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    vpn.dispose();
  });

  testWidgets('the export button copies the log as CSV and says so',
      (tester) async {
    final vpn = await pumpLogs(tester);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );

    await tester.tap(find.byTooltip('EXPORT LOGS (CSV)'));
    await tester.pump();

    expect(copied, startsWith('ID,Timestamp,Domain,Status,App'));
    expect(copied, contains('ads.Example.com'));
    expect(copied, contains('cdn.example.org'));
    expect(find.text('Copied 2 log entries to the clipboard as CSV.'),
        findsOneWidget);
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    vpn.dispose();
  });

  test('allowDomain and blockDomain keep the two lists disjoint', () async {
    SharedPreferences.setMockInitialValues({});
    final vpn = VpnProvider(enableSimulation: false);

    vpn.blockDomain('  Tracker.Example  ');
    expect(vpn.blacklist, ['tracker.example']);
    vpn.allowDomain('tracker.example');
    expect(vpn.whitelist, ['tracker.example']);
    expect(vpn.blacklist, isEmpty);
    vpn.blockDomain('tracker.example');
    expect(vpn.blacklist, ['tracker.example']);
    expect(vpn.whitelist, isEmpty);

    vpn.allowDomain('   ');
    vpn.blockDomain('');
    expect(vpn.whitelist, isEmpty);
    expect(vpn.blacklist, ['tracker.example']);
    vpn.dispose();
  });

  test('the log action strings exist in every language', () {
    const keys = [
      'logs_action_allow',
      'logs_action_unallow',
      'logs_action_block',
      'logs_action_unblock',
      'logs_action_copy',
      'logs_allow_added',
      'logs_block_added',
      'logs_rule_removed',
      'logs_copied',
      'logs_action_allow_for',
      'logs_allow_15m',
      'logs_allow_1h',
      'logs_allow_1d',
      'logs_allowed_until',
      'logs_timed_allow_added',
      'logs_timed_allow_stopped',
    ];
    for (final lang in AppStrings.languages) {
      for (final key in keys) {
        expect(AppStrings.rawFor(lang, key), isNotNull, reason: '$lang/$key');
      }
      for (final key in keys.where((key) => key.endsWith('ed'))) {
        expect(AppStrings.rawFor(lang, key), contains('{domain}'),
            reason: '$lang/$key');
      }
    }
  });
}
