import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aegis_net/src/i18n/app_strings.dart';
import 'package:aegis_net/src/providers/app_lock_provider.dart';
import 'package:aegis_net/src/providers/theme_provider.dart';
import 'package:aegis_net/src/providers/vpn_provider.dart';
import 'package:aegis_net/src/screens/app_lock_screen.dart';
import 'package:aegis_net/src/screens/logs_screen.dart';
import 'package:aegis_net/src/screens/settings_screen.dart';
import 'package:aegis_net/src/services/pin_hasher.dart';

DateTime clock = DateTime(2026, 11, 20, 9);

AppLockProvider newLock() => AppLockProvider(
      clock: () => clock,
      iterations: 10,
      hash: (pin, salt, iterations) async =>
          PinHasher.pbkdf2(utf8.encode(pin), salt, iterations),
    );

/// A lock that is on with [pin] and was not unlocked in the last minute.
Future<AppLockProvider> lockWithPin(String pin) async {
  final lock = newLock();
  await lock.ready;
  await lock.setPin(pin);
  clock = clock.add(const Duration(minutes: 2));
  return lock;
}

Future<void> typePin(WidgetTester tester, String pin) async {
  for (final d in pin.split('')) {
    await tester.tap(find.byKey(ValueKey('pin_key_$d')).last);
    await tester.pump();
  }
  await tester.tap(find.byKey(const ValueKey('pin_key_ok')).last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    AppStrings.lang = 'en';
    SharedPreferences.setMockInitialValues({});
  });

  group('lock screen', () {
    Future<AppLockProvider> pumpApp(WidgetTester tester) async {
      final first = await lockWithPin('2468');
      // A fresh start: the app reads the stored lock and opens locked.
      final lock = newLock();
      await lock.ready;
      first.dispose();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: lock,
          child: MaterialApp(
            home: const Scaffold(body: Text('dashboard')),
            builder: (context, child) => AppLockGate(child: child!),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return lock;
    }

    testWidgets('covers the app until the right PIN', (tester) async {
      final lock = await pumpApp(tester);
      expect(find.byKey(const ValueKey('app_lock_screen')), findsOneWidget);
      expect(find.text('AegisNet is locked'), findsOneWidget);

      await typePin(tester, '1111');
      expect(find.text('Wrong PIN'), findsOneWidget);
      expect(lock.isLocked, isTrue);

      await typePin(tester, '2468');
      expect(find.byKey(const ValueKey('app_lock_screen')), findsNothing);
      expect(find.text('dashboard'), findsOneWidget);
      lock.dispose();
    });

    testWidgets('says how long to wait after too many wrong tries',
        (tester) async {
      final lock = await pumpApp(tester);
      for (var i = 0; i < 5; i++) {
        await typePin(tester, '0000');
      }
      expect(find.text('Too many wrong tries. Try again in 30 s.'),
          findsOneWidget);

      await typePin(tester, '2468');
      expect(lock.isLocked, isTrue, reason: 'no PIN is checked while waiting');
      lock.dispose();
    });

    testWidgets('the OK key waits for at least four digits', (tester) async {
      final lock = await pumpApp(tester);
      for (final d in ['2', '4', '6']) {
        await tester.tap(find.byKey(ValueKey('pin_key_$d')));
      }
      await tester.pump();
      final ok = tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('pin_key_ok')));
      expect(ok.onPressed, isNull);
      lock.dispose();
    });

    testWidgets('locks again after a long stay in the background',
        (tester) async {
      final lock = await pumpApp(tester);
      await typePin(tester, '2468');
      expect(lock.isLocked, isFalse);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      clock = clock.add(const Duration(minutes: 1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('app_lock_screen')), findsOneWidget);
      lock.dispose();
    });
  });

  group('settings', () {
    Future<AppLockProvider> pumpCard(WidgetTester tester,
        {AppLockProvider? lock}) async {
      final l = lock ?? newLock();
      await l.ready;
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: l,
          child: const MaterialApp(
            home: Scaffold(body: Center(child: AppLockSettingsCard())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return l;
    }

    testWidgets('turning it on asks for the PIN twice', (tester) async {
      final lock = await pumpCard(tester);
      await tester.tap(find.byKey(const Key('app_lock_switch')));
      await tester.pumpAndSettle();
      expect(find.text('Choose a 4-6 digit PIN'), findsOneWidget);

      await typePin(tester, '13579');
      expect(find.text('Enter the same PIN again'), findsOneWidget);
      await typePin(tester, '13579');

      expect(lock.enabled, isTrue);
      expect(find.text('App lock is on.'), findsOneWidget);
      expect(await lock.check('13579'), PinCheck.ok);
      lock.dispose();
    });

    testWidgets('two different PINs start over and change nothing',
        (tester) async {
      final lock = await pumpCard(tester);
      await tester.tap(find.byKey(const Key('app_lock_switch')));
      await tester.pumpAndSettle();
      await typePin(tester, '1234');
      await typePin(tester, '4321');

      expect(find.text('The two PINs differ. Choose a PIN again.'),
          findsOneWidget);
      expect(find.text('Choose a 4-6 digit PIN'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pin_cancel')));
      await tester.pumpAndSettle();
      expect(lock.enabled, isFalse);
      lock.dispose();
    });

    testWidgets('turning it off needs the PIN, even right after entering it',
        (tester) async {
      final lock = newLock();
      await lock.ready;
      await lock.setPin('1234');
      expect(lock.confirmedRecently, isTrue);
      await pumpCard(tester, lock: lock);

      await tester.tap(find.byKey(const Key('app_lock_switch')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pin_check_dialog')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pin_cancel')));
      await tester.pumpAndSettle();
      expect(lock.enabled, isTrue);

      await tester.tap(find.byKey(const Key('app_lock_switch')));
      await tester.pumpAndSettle();
      await typePin(tester, '1234');
      expect(lock.enabled, isFalse);
      expect(find.text('App lock is off.'), findsOneWidget);
      lock.dispose();
    });

    testWidgets('changing the PIN asks for the old one first', (tester) async {
      final lock = await lockWithPin('1234');
      await pumpCard(tester, lock: lock);

      await tester.tap(find.byKey(const Key('app_lock_change')));
      await tester.pumpAndSettle();
      await typePin(tester, '9999');
      expect(find.text('Wrong PIN'), findsOneWidget);
      await typePin(tester, '1234');
      await typePin(tester, '8642');
      await typePin(tester, '8642');

      expect(find.text('PIN changed.'), findsOneWidget);
      expect(await lock.check('8642'), PinCheck.ok);
      expect(await lock.check('1234'), PinCheck.wrong);
      lock.dispose();
    });
  });

  group('actions that weaken protection', () {
    Future<VpnProvider> pumpLogs(
        WidgetTester tester, AppLockProvider lock) async {
      final vpn = VpnProvider(enableSimulation: false);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: vpn),
            ChangeNotifierProvider.value(value: ThemeProvider()),
            ChangeNotifierProvider.value(value: lock),
          ],
          child: const MaterialApp(home: LogsScreen()),
        ),
      );
      vpn.debugSetLogs([
        DnsLogItem(
          id: '1',
          domain: 'ads.example.com',
          isBlocked: true,
          timestamp: DateTime(2026, 11, 20, 9),
        ),
      ]);
      await tester.pumpAndSettle();
      await tester.tap(find.text('ads.example.com'));
      await tester.pumpAndSettle();
      return vpn;
    }

    testWidgets('allowing a domain waits for the PIN', (tester) async {
      final lock = await lockWithPin('1234');
      final vpn = await pumpLogs(tester, lock);

      await tester.tap(find.byKey(const ValueKey('log-action-allow')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pin_check_dialog')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pin_cancel')));
      await tester.pumpAndSettle();
      expect(vpn.whitelist, isEmpty);

      await tester.tap(find.byKey(const ValueKey('log-action-allow')));
      await tester.pumpAndSettle();
      await typePin(tester, '1234');
      expect(vpn.whitelist, ['ads.example.com']);
      vpn.dispose();
      lock.dispose();
    });

    testWidgets('a PIN entered a moment ago is not asked again',
        (tester) async {
      final lock = await lockWithPin('1234');
      expect(await lock.check('1234'), PinCheck.ok);
      final vpn = await pumpLogs(tester, lock);

      await tester.tap(find.byKey(const ValueKey('log-action-allow-1h')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pin_check_dialog')), findsNothing);
      expect(vpn.temporaryAllowUntil('ads.example.com'), isNotNull);
      vpn.dispose();
      lock.dispose();
    });

    testWidgets('blocking a domain never asks', (tester) async {
      final lock = await lockWithPin('1234');
      final vpn = await pumpLogs(tester, lock);

      await tester.tap(find.byKey(const ValueKey('log-action-block')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pin_check_dialog')), findsNothing);
      expect(vpn.blacklist, ['ads.example.com']);
      vpn.dispose();
      lock.dispose();
    });

    testWidgets('with the lock off nothing asks', (tester) async {
      final lock = newLock();
      await lock.ready;
      final vpn = await pumpLogs(tester, lock);

      await tester.tap(find.byKey(const ValueKey('log-action-allow')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pin_check_dialog')), findsNothing);
      expect(vpn.whitelist, ['ads.example.com']);
      vpn.dispose();
      lock.dispose();
    });
  });

  group('settings switches', () {
    const channel = MethodChannel('com.aegisnet/vpn');
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getVpnDiagnostics') {
          return <String, dynamic>{'sdkInt': 34};
        }
        return null;
      });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    testWidgets('switching a blocking option off needs the PIN, on does not',
        (tester) async {
      final lock = await lockWithPin('1234');
      final vpn = VpnProvider(enableSimulation: false);
      await tester.runAsync(() => vpn.ready);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: vpn),
            ChangeNotifierProvider.value(value: ThemeProvider()),
            ChangeNotifierProvider.value(value: lock),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final cname = find.byKey(const Key('cname_switch'));
      await tester.scrollUntilVisible(cname, 300,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(cname);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pin_check_dialog')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pin_cancel')));
      await tester.pumpAndSettle();
      expect(vpn.blockAliasTrackers, isTrue);

      await tester.tap(cname);
      await tester.pumpAndSettle();
      await typePin(tester, '1234');
      expect(vpn.blockAliasTrackers, isFalse);

      // Turning it back on strengthens protection: no PIN, even later.
      clock = clock.add(const Duration(minutes: 2));
      await tester.tap(cname);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pin_check_dialog')), findsNothing);
      expect(vpn.blockAliasTrackers, isTrue);
      vpn.dispose();
      lock.dispose();
    });
  });
}
