import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:aegis_net/src/services/download_roots.dart';

void main() {
  test('the bundled ISRG roots are valid certificates on their own', () {
    // Loaded into a context with no system roots at all, the way Android 7.0
    // effectively sees them. A truncated or mangled PEM throws here.
    final context = SecurityContext(withTrustedRoots: false);
    expect(
      () => context.setTrustedCertificatesBytes(utf8.encode(isrgRootsPem)),
      returnsNormally,
    );
  });

  test('both ISRG roots are bundled', () {
    expect(
      RegExp('-----BEGIN CERTIFICATE-----').allMatches(isrgRootsPem).length,
      2,
    );
  });

  test('the download context builds on this platform', () {
    expect(downloadSecurityContext(), isNotNull);
  });
}
