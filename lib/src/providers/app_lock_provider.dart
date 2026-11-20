import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/pin_hasher.dart';

/// Result of checking a PIN.
enum PinCheck { ok, wrong, lockedOut }

typedef PinHashFn = Future<List<int>> Function(
    String pin, List<int> salt, int iterations);

/// Optional PIN lock, so someone else holding the phone cannot switch
/// protection off or loosen the filters.
///
/// Only a PBKDF2 hash of the PIN and its random salt are stored. Wrong tries
/// are counted across restarts; from the fifth one on, each wrong try starts a
/// wait (30 s, doubling, at most 15 minutes) during which no PIN is checked.
class AppLockProvider extends ChangeNotifier {
  AppLockProvider({
    DateTime Function()? clock,
    this.iterations = defaultIterations,
    PinHashFn? hash,
    Random? random,
  })  : _now = clock ?? DateTime.now,
        _hash = hash ?? PinHasher.hashPin,
        _random = random ?? Random.secure() {
    ready = _load();
  }

  static const int defaultIterations = 100000;
  static const int minLength = 4;
  static const int maxLength = 6;

  /// Time in the background after which the app asks for the PIN again.
  static const Duration relockAfter = Duration(seconds: 30);

  /// A PIN typed this recently also covers an action that weakens protection,
  /// so turning off two filters in a row does not ask twice.
  static const Duration confirmGrace = Duration(minutes: 1);

  static const int freeTries = 5;
  static const Duration firstWait = Duration(seconds: 30);
  static const Duration maxWait = Duration(minutes: 15);

  static const _kHash = 'app_lock_hash';
  static const _kSalt = 'app_lock_salt';
  static const _kIterations = 'app_lock_iterations';
  static const _kFailures = 'app_lock_failures';
  static const _kLockoutUntil = 'app_lock_lockout_until';

  /// Iterations used for a PIN set from now on. A stored PIN keeps the count
  /// it was hashed with.
  final int iterations;
  final DateTime Function() _now;
  final PinHashFn _hash;
  final Random _random;

  late final Future<void> ready;

  bool _loaded = false;
  List<int>? _storedHash;
  List<int>? _salt;
  int _storedIterations = defaultIterations;
  int _failures = 0;
  DateTime? _lockoutUntil;
  bool _locked = false;
  DateTime? _backgroundAt;
  DateTime? _confirmedAt;

  bool get loaded => _loaded;
  bool get enabled => _storedHash != null;
  bool get isLocked => enabled && _locked;

  static bool isValidPin(String pin) =>
      RegExp('^[0-9]{$minLength,$maxLength}\$').hasMatch(pin);

  Duration get lockoutRemaining {
    final until = _lockoutUntil;
    if (until == null) return Duration.zero;
    final left = until.difference(_now());
    return left.isNegative ? Duration.zero : left;
  }

  bool get confirmedRecently {
    final at = _confirmedAt;
    return at != null && _now().difference(at) <= confirmGrace;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final hash = prefs.getString(_kHash);
    final salt = prefs.getString(_kSalt);
    if (hash != null && salt != null) {
      try {
        _storedHash = base64Decode(hash);
        _salt = base64Decode(salt);
      } on FormatException {
        _storedHash = null;
        _salt = null;
      }
    }
    _storedIterations = prefs.getInt(_kIterations) ?? defaultIterations;
    _failures = prefs.getInt(_kFailures) ?? 0;
    final until = prefs.getInt(_kLockoutUntil);
    _lockoutUntil =
        until == null ? null : DateTime.fromMillisecondsSinceEpoch(until);
    _locked = enabled;
    _loaded = true;
    notifyListeners();
  }

  /// Turns the lock on, or replaces the PIN when it is already on. The caller
  /// asks for the current PIN before a change.
  Future<void> setPin(String pin) async {
    if (!isValidPin(pin)) throw ArgumentError('PIN must be 4-6 digits');
    final salt = List<int>.generate(16, (_) => _random.nextInt(256));
    final hash = await _hash(pin, salt, iterations);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSalt, base64Encode(salt));
    await prefs.setString(_kHash, base64Encode(hash));
    await prefs.setInt(_kIterations, iterations);
    await _saveFailures(prefs, 0, null);

    _salt = salt;
    _storedHash = hash;
    _storedIterations = iterations;
    _locked = false;
    _confirmedAt = _now();
    notifyListeners();
  }

  /// Turns the lock off. The caller asks for the PIN first.
  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kHash);
    await prefs.remove(_kSalt);
    await prefs.remove(_kIterations);
    await _saveFailures(prefs, 0, null);
    _storedHash = null;
    _salt = null;
    _locked = false;
    _confirmedAt = null;
    notifyListeners();
  }

  /// Checks [pin] without changing whether the app is locked.
  Future<PinCheck> check(String pin) async {
    final stored = _storedHash;
    final salt = _salt;
    if (stored == null || salt == null) return PinCheck.ok;
    if (lockoutRemaining > Duration.zero) return PinCheck.lockedOut;

    final candidate = await _hash(pin, salt, _storedIterations);
    final prefs = await SharedPreferences.getInstance();
    if (_sameBytes(candidate, stored)) {
      if (_failures != 0 || _lockoutUntil != null) {
        await _saveFailures(prefs, 0, null);
      }
      _confirmedAt = _now();
      notifyListeners();
      return PinCheck.ok;
    }

    final failures = _failures + 1;
    DateTime? until;
    if (failures >= freeTries) {
      final doublings = min(failures - freeTries, 20);
      var wait = firstWait * (1 << doublings);
      if (wait > maxWait) wait = maxWait;
      until = _now().add(wait);
    }
    await _saveFailures(prefs, failures, until);
    notifyListeners();
    return PinCheck.wrong;
  }

  /// [check], and unlock the app when it passes.
  Future<PinCheck> unlock(String pin) async {
    final result = await check(pin);
    if (result == PinCheck.ok && _locked) {
      _locked = false;
      notifyListeners();
    }
    return result;
  }

  void lock() {
    if (!enabled || _locked) return;
    _locked = true;
    _confirmedAt = null;
    notifyListeners();
  }

  void onBackground() {
    _backgroundAt ??= _now();
    _confirmedAt = null;
  }

  void onForeground() {
    final since = _backgroundAt;
    _backgroundAt = null;
    if (since != null && _now().difference(since) > relockAfter) lock();
  }

  Future<void> _saveFailures(
      SharedPreferences prefs, int failures, DateTime? until) async {
    _failures = failures;
    _lockoutUntil = until;
    if (failures == 0) {
      await prefs.remove(_kFailures);
    } else {
      await prefs.setInt(_kFailures, failures);
    }
    if (until == null) {
      await prefs.remove(_kLockoutUntil);
    } else {
      await prefs.setInt(_kLockoutUntil, until.millisecondsSinceEpoch);
    }
  }

  /// Compares every byte, so the time taken does not say how much matched.
  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
