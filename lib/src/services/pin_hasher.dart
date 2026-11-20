import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// PBKDF2 with HMAC-SHA256 (RFC 8018), used to keep the app-lock PIN out of
/// storage. Only the derived key and its salt are saved.
class PinHasher {
  /// Derives [length] bytes from [password] and [salt].
  static Uint8List pbkdf2(
    List<int> password,
    List<int> salt,
    int iterations, {
    int length = 32,
  }) {
    if (iterations < 1) throw ArgumentError.value(iterations, 'iterations');
    final hmac = Hmac(sha256, password);
    final out = BytesBuilder(copy: false);
    var block = 1;
    while (out.length < length) {
      final blockIndex = Uint8List(4)..buffer.asByteData().setUint32(0, block);
      var u = hmac.convert([...salt, ...blockIndex]).bytes;
      final t = Uint8List.fromList(u);
      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      out.add(t);
      block++;
    }
    return Uint8List.sublistView(out.takeBytes(), 0, length);
  }

  /// [pbkdf2] for a PIN, off the UI thread where the platform allows it, so
  /// the lock screen does not freeze while the key is derived.
  static Future<List<int>> hashPin(String pin, List<int> salt, int iterations) {
    return compute(_hashEntry, _HashJob(pin, salt, iterations));
  }

  static List<int> _hashEntry(_HashJob job) =>
      pbkdf2(utf8.encode(job.pin), job.salt, job.iterations);
}

class _HashJob {
  const _HashJob(this.pin, this.salt, this.iterations);
  final String pin;
  final List<int> salt;
  final int iterations;
}
