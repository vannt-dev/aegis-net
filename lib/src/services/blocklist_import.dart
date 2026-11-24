/// Reading a blocklist file the user picked from their own storage.
///
/// Two shapes are understood, the two that block lists are usually shared in:
///
/// * a hosts file: `0.0.0.0 ads.example.com`, one or more names after an
///   address that goes nowhere (0.0.0.0, 127.0.0.1, :: or ::1);
/// * a domain list: one name per line.
///
/// `#` starts a comment anywhere on a line, and `!` a comment line. Anything
/// else is skipped and counted, so the user can tell when a file was not what
/// they thought it was.
class BlocklistImport {
  /// Every name to block, lowercase, each once, in the order the file
  /// first listed them.
  final List<String> domains;

  /// Names that appeared more than once and were kept only once.
  final int duplicates;

  /// Lines that held something other than a name to block.
  final int skipped;

  const BlocklistImport({
    required this.domains,
    required this.duplicates,
    required this.skipped,
  });

  /// Addresses a hosts file points a name at to block it.
  static const _sinkholes = {
    '0.0.0.0',
    '127.0.0.1',
    '::',
    '::1',
    '0:0:0:0:0:0:0:0',
    '0:0:0:0:0:0:0:1',
  };

  /// Names a stock hosts file maps to the machine itself. Blocking them would
  /// break the device, not an advertiser.
  static const _localNames = {
    'localhost',
    'localhost.localdomain',
    'local',
    'broadcasthost',
    'ip6-localhost',
    'ip6-loopback',
    'ip6-localnet',
    'ip6-mcastprefix',
    'ip6-allnodes',
    'ip6-allrouters',
    'ip6-allhosts',
    '0.0.0.0',
  };

  static final _label = RegExp(r'^[a-z0-9_](?:[a-z0-9_-]{0,61}[a-z0-9_])?$');
  static final _ipv4 = RegExp(r'^\d{1,3}(?:\.\d{1,3}){3}$');

  /// The name [raw] stands for, or null when it is not one a DNS filter can
  /// block: a bare word, an IP address, a wildcard, a name with a space or a
  /// character DNS does not allow.
  static String? normaliseDomain(String raw) {
    var name = raw.trim().toLowerCase();
    if (name.endsWith('.')) name = name.substring(0, name.length - 1);
    if (name.isEmpty || name.length > 253) return null;
    if (_localNames.contains(name) || _ipv4.hasMatch(name)) return null;
    final labels = name.split('.');
    // A single word ("ads") is not a name anyone can look up on the internet.
    if (labels.length < 2) return null;
    for (final label in labels) {
      if (!_label.hasMatch(label)) return null;
    }
    // The last label of a real name is never all digits.
    if (RegExp(r'^\d+$').hasMatch(labels.last)) return null;
    return name;
  }

  static bool _isAddress(String token) =>
      _ipv4.hasMatch(token) || (token.contains(':') && !token.contains('.'));

  /// Read [text] as a hosts file or a domain list, or both mixed.
  static BlocklistImport parse(String text) {
    // A byte order mark from a Windows editor would glue itself to the first
    // name and make it invalid.
    if (text.startsWith('﻿')) text = text.substring(1);

    final seen = <String>{};
    final domains = <String>[];
    var duplicates = 0;
    var skipped = 0;

    void add(String name) {
      if (seen.add(name)) {
        domains.add(name);
      } else {
        duplicates++;
      }
    }

    for (var line in text.split(RegExp(r'\r?\n|\r'))) {
      final hash = line.indexOf('#');
      if (hash >= 0) line = line.substring(0, hash);
      line = line.trim();
      if (line.isEmpty || line.startsWith('!')) continue;

      final tokens = line.split(RegExp(r'\s+'));
      if (_isAddress(tokens.first)) {
        // A hosts line. One pointing somewhere real is a redirect, not a
        // block, and is not this importer's to turn into one.
        if (!_sinkholes.contains(tokens.first) || tokens.length < 2) {
          skipped++;
          continue;
        }
        var any = false;
        for (final token in tokens.skip(1)) {
          final name = normaliseDomain(token);
          if (name == null) continue;
          add(name);
          any = true;
        }
        // "127.0.0.1 localhost" is an ordinary hosts line, but nothing to
        // block; it is still worth telling the user it was left out.
        if (!any) skipped++;
        continue;
      }

      final name = tokens.length == 1 ? normaliseDomain(tokens.first) : null;
      if (name == null) {
        skipped++;
      } else {
        add(name);
      }
    }

    return BlocklistImport(
      domains: domains,
      duplicates: duplicates,
      skipped: skipped,
    );
  }

  /// The list in hosts form, the shape the engine already reads from the
  /// bundled sources, with a first line saying where it came from.
  String toHostsText({String? source}) {
    final out = StringBuffer();
    if (source != null && source.isNotEmpty) {
      out.writeln(
          '# Imported from ${source.replaceAll(RegExp(r'[\r\n]'), ' ')}');
    }
    for (final name in domains) {
      out.writeln('0.0.0.0 $name');
    }
    return out.toString();
  }
}
