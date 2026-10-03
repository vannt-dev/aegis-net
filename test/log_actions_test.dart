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
