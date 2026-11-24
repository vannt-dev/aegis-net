import 'dart:io';

import 'package:aegis_net/src/bridge/aegis_bridge.dart';
import 'package:aegis_net/src/services/blocklist_import.dart';
import 'package:aegis_net/src/services/rule_downloader_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A blocklist picked from the phone's own storage: what the parser accepts,
/// and how the list is kept next to the downloaded ones.
void main() {
  group('parse', () {
    test('reads a hosts file, several names per line included', () {
      final result = BlocklistImport.parse('''
# a comment
0.0.0.0 ads.example.com
127.0.0.1 tracker.example.net metrics.example.net
:: v6.example.org
::1 v6loop.example.org
''');
      expect(result.domains, [
        'ads.example.com',
        'tracker.example.net',
        'metrics.example.net',
        'v6.example.org',
        'v6loop.example.org',
      ]);
      expect(result.skipped, 0);
      expect(result.duplicates, 0);
    });

    test('reads a domain list with Windows line ends, a BOM and comments', () {
      final result = BlocklistImport.parse(
          '﻿Ads.Example.com\r\n! adblock-style comment\r\n'
          'cdn.example.com. # trailing dot and comment\r\n\r\n');
      expect(result.domains, ['ads.example.com', 'cdn.example.com']);
      expect(result.skipped, 0);
    });

    test('keeps each name once and counts the repeats', () {
      final result = BlocklistImport.parse(
          'a.example.com\n0.0.0.0 a.example.com\nA.EXAMPLE.COM\nb.example.com\n');
      expect(result.domains, ['a.example.com', 'b.example.com']);
      expect(result.duplicates, 2);
    });

    test('skips what is not a name to block, and counts it', () {
      final result = BlocklistImport.parse('''
127.0.0.1 localhost
::1 ip6-localhost ip6-loopback
255.255.255.255 broadcasthost
192.168.1.10 nas.example.com
ads
*.wildcard.example.com
||adblock.example.com^
two words.example.com
bad_-.example.com
-leading.example.com
1.2.3.4
host.123
good.example.com
''');
      expect(result.domains, ['good.example.com']);
      expect(result.skipped, 12);
    });

    test('rejects over-long names and labels', () {
      final longLabel = '${'a' * 64}.example.com';
      final okLabel = '${'a' * 63}.example.com';
      final longName = '${List.filled(64, 'abc').join('.')}.com';
      expect(BlocklistImport.normaliseDomain(longLabel), isNull);
      expect(BlocklistImport.normaliseDomain(okLabel), okLabel);
      expect(BlocklistImport.normaliseDomain(longName), isNull);
    });

    test('writes the list back in hosts form', () {
      final text = BlocklistImport.parse('a.example.com\nb.example.com\n')
          .toHostsText(source: 'my\nlist.txt');
      expect(text,
          '# Imported from my list.txt\n0.0.0.0 a.example.com\n0.0.0.0 b.example.com\n');
    });
  });

  group('importFromFile', () {
    late Directory dir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'disabled_filter_sources': ['hagezi_multi', 'stevenblack_porn'],
      });
      dir = await Directory.systemTemp.createTemp('aegis_import_');
      RuleDownloaderService.cacheDirForTest = dir;
      await RuleDownloaderService.loadSources();
      AegisBridge.clearDownloadedRules();
    });

    tearDown(() async {
      RuleDownloaderService.fetcher = RuleDownloaderService.fetchFilterContent;
      RuleDownloaderService.cacheDirForTest = null;
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('adds the list, blocks its names at once and keeps it saved',
        () async {
      final outcome = await RuleDownloaderService.importFromFile(
        fileName: 'family-blocklist.txt',
        text: '0.0.0.0 imported-one.example\nimported-two.example\n'
            'imported-two.example\nnot a domain\n',
      );

      expect(outcome.status, ImportStatus.added);
      expect(outcome.parsed.domains.length, 2);
      expect(outcome.parsed.duplicates, 1);
      expect(outcome.parsed.skipped, 1);
      final source = outcome.source!;
      expect(source.isLocal, isTrue);
      expect(source.name, 'family-blocklist');
      expect(AegisBridge.isDomainBlocked('imported-one.example'), isTrue);
      expect(AegisBridge.isDomainBlocked('imported-two.example'), isTrue);

      // Kept across a restart like any list, without the network.
      AegisBridge.clearDownloadedRules();
      await RuleDownloaderService.loadSources();
      expect(RuleDownloaderService.allSources.map((s) => s.id),
          contains(source.id));
      await RuleDownloaderService.loadCachedFilters();
      expect(AegisBridge.isDomainBlocked('imported-two.example'), isTrue);
    });

    test('a sync keeps the imported list and never tries to download it',
        () async {
      final outcome = await RuleDownloaderService.importFromFile(
          fileName: 'mine', text: 'synced-import.example\n');
      final asked = <String>[];
      RuleDownloaderService.fetcher = (url) async {
        asked.add(url);
        return 'preset.example\n';
      };

      await RuleDownloaderService.syncAllFilters();

      expect(asked, isNot(contains(outcome.source!.url)));
      expect(AegisBridge.isDomainBlocked('synced-import.example'), isTrue);
      expect(await RuleDownloaderService.needsSync(), isFalse);
    });

    test('the same names imported twice are refused', () async {
      await RuleDownloaderService.importFromFile(
          fileName: 'a.txt', text: 'x.example.com\ny.example.com\n');
      final again = await RuleDownloaderService.importFromFile(
          fileName: 'b.hosts', text: '0.0.0.0 x.example.com y.example.com\n');
      expect(again.status, ImportStatus.duplicate);
      expect(
          RuleDownloaderService.allSources.where((s) => s.isLocal).length, 1);
    });

    test('a file with nothing to block adds nothing', () async {
      final outcome = await RuleDownloaderService.importFromFile(
          fileName: 'notes.txt', text: 'hello world\n127.0.0.1 localhost\n');
      expect(outcome.status, ImportStatus.empty);
      expect(RuleDownloaderService.allSources.where((s) => s.isLocal), isEmpty);
    });

    test('removing the list unblocks its names and deletes the copy', () async {
      final outcome = await RuleDownloaderService.importFromFile(
          fileName: 'gone.txt', text: 'removed-import.example\n');
      final saved = dir.listSync().whereType<File>().length;

      await RuleDownloaderService.removeImported(outcome.source!.id);

      expect(AegisBridge.isDomainBlocked('removed-import.example'), isFalse);
      expect(dir.listSync().whereType<File>().length, saved - 1);
      expect(RuleDownloaderService.allSources.where((s) => s.isLocal), isEmpty);
    });
  });
}
