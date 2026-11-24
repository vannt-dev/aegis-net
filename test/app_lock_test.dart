import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aegis_net/src/providers/app_lock_provider.dart';
import 'package:aegis_net/src/services/pin_hasher.dart';

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// A provider whose clock the test moves by hand and whose hashing runs on
/// the test thread with few iterations, so nothing waits on an isolate.
class Harness {
  DateTime now = DateTime(2026, 11, 20, 9);
  late final AppLockProvider lock = AppLockProvider(
    clock: () => now,
    iterations: 10,
    hash: (pin, salt, iterations) async =>
        PinHasher.pbkdf2(utf8.encode(pin), salt, iterations),
  );
}

void main() {
  group('PBKDF2-HMAC-SHA256', () {
    // Published test vectors for PBKDF2 with HMAC-SHA256.
    test('matches the known vectors', () {
      final password = utf8.encode('password');
      final salt = utf8.encode('salt');
      expect(hex(PinHasher.pbkdf2(password, salt, 1)),
          '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b');
      expect(hex(PinHasher.pbkdf2(password, salt, 2)),
          'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43');
      expect(hex(PinHasher.pbkdf2(password, salt, 4096)),
          'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a');
    });

    test('derives more than one block when asked', () {
      final key = PinHasher.pbkdf2(
          utf8.encode('passwd'), utf8.encode('salt'), 1,
          length: 64);
      expect(
          hex(key),
          '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc'
          '49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783');
    });
  });

  test('hashPin runs the same derivation off the UI thread', () async {
    final salt = List<int>.generate(16, (i) => i);
    expect(await PinHasher.hashPin('1234', salt, 50),
        PinHasher.pbkdf2(utf8.encode('1234'), salt, 50));
  });

  group('PIN rules', () {
    test('accepts 4 to 6 digits only', () {
      expect(AppLockProvider.isValidPin('1234'), isTrue);
      expect(AppLockProvider.isValidPin('123456'), isTrue);
      expect(AppLockProvider.isValidPin('123'), isFalse);
      expect(AppLockProvider.isValidPin('1234567'), isFalse);
      expect(AppLockProvider.isValidPin('12a4'), isFalse);
      expect(AppLockProvider.isValidPin(' 1234'), isFalse);
    });
  });

  group('AppLockProvider', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('is off and unlocked by default', () async {
      final h = Harness();
      await h.lock.ready;
      expect(h.lock.enabled, isFalse);
      expect(h.lock.isLocked, isFalse);
    });

    test('stores a salted hash, never the PIN', () async {
      final h = Harness();
      await h.lock.ready;
      await h.lock.setPin('482913');

      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getKeys().map((k) => '${prefs.get(k)}').join('|');
      expect(stored, isNot(contains('482913')));
      expect(prefs.getString('app_lock_hash'), isNotEmpty);
      expect(prefs.getString('app_lock_salt'), isNotEmpty);
      expect(prefs.getInt('app_lock_iterations'), 10);
    });

    test('two locks with the same PIN get different salts and hashes',
        () async {
      final a = Harness();
      await a.lock.ready;
      await a.lock.setPin('1234');
      final prefs = await SharedPreferences.getInstance();
      final firstSalt = prefs.getString('app_lock_salt');
      final firstHash = prefs.getString('app_lock_hash');

      await a.lock.setPin('1234');
      expect(prefs.getString('app_lock_salt'), isNot(firstSalt));
      expect(prefs.getString('app_lock_hash'), isNot(firstHash));
    });

    test('checks the PIN', () async {
      final h = Harness();
      await h.lock.ready;
      await h.lock.setPin('1234');

      expect(await h.lock.check('1234'), PinCheck.ok);
      expect(await h.lock.check('4321'), PinCheck.wrong);
    });

    test('a new instance reads the lock back and starts locked', () async {
      final first = Harness();
      await first.lock.ready;
      await first.lock.setPin('1234');

      final second = Harness();
      await second.lock.ready;
      expect(second.lock.enabled, isTrue);
      expect(second.lock.isLocked, isTrue);
      expect(await second.lock.unlock('1234'), PinCheck.ok);
      expect(second.lock.isLocked, isFalse);
    });

    test('a wrong PIN leaves it locked', () async {
      final h = Harness();
      await h.lock.ready;
      await h.lock.setPin('1234');
      h.lock.lock();

      expect(await h.lock.unlock('9999'), PinCheck.wrong);
      expect(h.lock.isLocked, isTrue);
    });

    test('five wrong tries lock out for 30 s, then the wait doubles', () async {
      final h = Harness();
      await h.lock.ready;
      await h.lock.setPin('1234');

      for (var i = 0; i < 4; i++) {
        expect(await h.lock.check('0000'), PinCheck.wrong);
      }
      expect(h.lock.lockoutRemaining, Duration.zero);
      expect(await h.lock.check('0000'), PinCheck.wrong);
      expect(h.lock.lockoutRemaining, const Duration(seconds: 30));

      // Even the right PIN is refused while the wait runs.
      expect(await h.lock.check('1234'), PinCheck.lockedOut);

      h.now = h.now.add(const Duration(seconds: 31));
      expect(await h.lock.check('0000'), PinCheck.wrong);
      expect(h.lock.lockoutRemaining, const Duration(seconds: 60));
    });

    test('the lockout survives a restart', () async {
      final first = Harness();
      await first.lock.ready;
      await first.lock.setPin('1234');
      for (var i = 0; i < 5; i++) {
        await first.lock.check('0000');
      }

      final second = Harness()..now = first.now;
      await second.lock.ready;
      expect(second.lock.lockoutRemaining, const Duration(seconds: 30));
      expect(await second.lock.unlock('1234'), PinCheck.lockedOut);
    });

    test('the right PIN clears the wrong-try count', () async {
      final h = Harness();
      await h.lock.ready;
      await h.lock.setPin('1234');
      for (var i = 0; i < 4; i++) {
        await h.lock.check('0000');
      }
      expect(await h.lock.check('1234'), PinCheck.ok);
      expect(await h.lock.check('0000'), PinCheck.wrong);
      expect(h.lock.lockoutRemaining, Duration.zero);
    });

    test('the wait is capped at 15 minutes', () async {
      final h = Harness();
      await h.lock.ready;
      await h.lock.setPin('1234');
      for (var i = 0; i < 20; i++) {
        h.now = h.now.add(const Duration(hours: 1));
        await h.lock.check('0000');
      }
      expect(h.lock.lockoutRemaining, const Duration(minutes: 15));
    });

    test('locks again after more than 30 s in the background', () async {
      final h = Harness();
      await h.lock.ready;
      await h.lock.setPin('1234');
      expect(h.lock.isLocked, isFalse);

      h.lock.onBackground();
      h.now = h.now.add(const Duration(seconds: 20));
      h.lock.onForeground();
      expect(h.lock.isLocked, isFalse);

      h.lock.onBackground();
      h.now = h.now.add(const Duration(seconds: 31));
      h.lock.onForeground();
      expect(h.lock.isLocked, isTrue);
    });

    test('a PIN entered in the last minute covers a guarded action', () async {
      final h = Harness();
      await h.lock.ready;
      await h.lock.setPin('1234');
      expect(h.lock.confirmedRecently, isTrue);

      h.now = h.now.add(const Duration(seconds: 61));
      expect(h.lock.confirmedRecently, isFalse);

      expect(await h.lock.check('1234'), PinCheck.ok);
      expect(h.lock.confirmedRecently, isTrue);

      // Leaving the app ends the grace even if it does not relock.
      h.lock.onBackground();
      h.lock.onForeground();
      expect(h.lock.confirmedRecently, isFalse);
    });

    test('turning it off removes the hash', () async {
      final h = Harness();
      await h.lock.ready;
      await h.lock.setPin('1234');
      await h.lock.disable();

      expect(h.lock.enabled, isFalse);
      expect(h.lock.isLocked, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_lock_hash'), isNull);
      expect(prefs.getString('app_lock_salt'), isNull);
    });

    test('changing the PIN retires the old one', () async {
      final h = Harness();
      await h.lock.ready;
      await h.lock.setPin('1234');
      await h.lock.setPin('567890');

      expect(await h.lock.check('1234'), PinCheck.wrong);
      expect(await h.lock.check('567890'), PinCheck.ok);
    });

    test('refuses to store an invalid PIN', () async {
      final h = Harness();
      await h.lock.ready;
      expect(() => h.lock.setPin('12'), throwsArgumentError);
      expect(h.lock.enabled, isFalse);
    });
  });
}
