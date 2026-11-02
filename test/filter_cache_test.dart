import 'dart:io';

import 'package:aegis_net/src/bridge/aegis_bridge.dart';
import 'package:aegis_net/src/services/rule_downloader_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Downloaded filter lists used to live only in the engine's memory, so every
/// restart of the app (an update, a reboot, the system killing it) left the
/// phone filtering with the handful of built-in seed rules until someone
/// tapped Sync. These tests pin the fix: each list is kept on disk and loaded
/// back at start, and a failed download no longer throws a list away.
void main() {
  late Directory dir;
  // url -> list text; a missing url fails like a dead download.
  late Map<String, String> served;

  String urlOf(String id) =>
      RuleDownloaderService.allSources.firstWhere((s) => s.id == id).url;

  Future<void> restartApp() async {
    // A new process starts with an empty engine and no sources loaded.
    AegisBridge.clearDownloadedRules();
  }

  setUp(() async {
    // The preset sources are shared objects, so a toggle made by one test
    // would leak into the next unless the stored state is set every time.
    SharedPreferences.setMockInitialValues({
      'disabled_filter_sources': ['hagezi_multi', 'stevenblack_porn'],
    });
    dir = await Directory.systemTemp.createTemp('aegis_lists_');
    RuleDownloaderService.cacheDirForTest = dir;
    await RuleDownloaderService.loadSources();
    served = {
      for (final s in RuleDownloaderService.allSources)
        s.url: '${s.id}.example\n',
      urlOf('adguard_dns'): 'ads-only-in-adguard.example\n',
      urlOf('urlhaus'): '# hosts\nmalware-only.example\n',
    };
    RuleDownloaderService.fetcher = (url) async => served[url];
    AegisBridge.clearDownloadedRules();
  });

  tearDown(() async {
    RuleDownloaderService.fetcher = RuleDownloaderService.fetchFilterContent;
    RuleDownloaderService.cacheDirForTest = null;
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('lists synced once are back after a restart, with no network', () async {
    await RuleDownloaderService.syncAllFilters();
    expect(AegisBridge.isDomainBlocked('malware-only.example'), isTrue);

    await restartApp();
    expect(AegisBridge.isDomainBlocked('malware-only.example'), isFalse);

    served.clear(); // offline
    final loaded = await RuleDownloaderService.loadCachedFilters();
    expect(loaded, greaterThan(0));
    expect(AegisBridge.isDomainBlocked('malware-only.example'), isTrue);
    expect(AegisBridge.isDomainBlocked('ads-only-in-adguard.example'), isTrue);
  });

  test('a failed download keeps the copy from the last sync', () async {
    await RuleDownloaderService.syncAllFilters();

    served.remove(urlOf('urlhaus')); // this list's host is down today
    await RuleDownloaderService.syncAllFilters();

    expect(AegisBridge.isDomainBlocked('malware-only.example'), isTrue);
    expect(AegisBridge.isDomainBlocked('ads-only-in-adguard.example'), isTrue);
  });

  test('a list switched off is not loaded from its saved copy', () async {
    await RuleDownloaderService.syncAllFilters();
    await RuleDownloaderService.setSourceEnabled('urlhaus', false);

    await restartApp();
    await RuleDownloaderService.loadCachedFilters();

    expect(AegisBridge.isDomainBlocked('malware-only.example'), isFalse);
    expect(AegisBridge.isDomainBlocked('ads-only-in-adguard.example'), isTrue);
  });

  test('with nothing saved, start-up leaves the engine as it is', () async {
    // Rules already in the engine (a tunnel that outlived the screen) must
    // not be wiped by a start-up that has nothing to put back.
    AegisBridge.loadRulesText('in-memory-only.example\n');
    final loaded = await RuleDownloaderService.loadCachedFilters();
    expect(loaded, 0);
    expect(AegisBridge.isDomainBlocked('in-memory-only.example'), isTrue);
  });

  test('a sync is due when never synced, or more than a day ago', () async {
    expect(await RuleDownloaderService.needsSync(), isTrue);

    await RuleDownloaderService.syncAllFilters();
    expect(await RuleDownloaderService.needsSync(), isFalse);

    final prefs = await SharedPreferences.getInstance();
    final dayAndAMinuteAgo = DateTime.now()
        .subtract(const Duration(hours: 24, minutes: 1))
        .millisecondsSinceEpoch;
    await prefs.setInt(RuleDownloaderService.prefLastSync, dayAndAMinuteAgo);
    expect(await RuleDownloaderService.needsSync(), isTrue);
  });

  test('a sync where every download failed is not counted', () async {
    served.clear();
    await RuleDownloaderService.syncAllFilters();
    expect(await RuleDownloaderService.needsSync(), isTrue);
  });

  test('a switched-on list with no saved copy makes a sync due', () async {
    await RuleDownloaderService.syncAllFilters();
    await RuleDownloaderService.setSourceEnabled('hagezi_multi', true);
    expect(await RuleDownloaderService.needsSync(), isTrue);
  });

  test('removing a custom list removes its saved copy too', () async {
    const url = 'https://lists.example/mine.txt';
    served[url] = 'mine.example\n';
    await RuleDownloaderService.addCustomSource(FilterSource(
      id: 'custom_mine',
      name: 'Mine',
      url: url,
      description: 'test',
    ));
    await RuleDownloaderService.syncAllFilters();
    bool saved() =>
        dir.listSync().any((e) => e.uri.pathSegments.last == 'custom_mine.txt');
    expect(saved(), isTrue);

    await RuleDownloaderService.removeCustomSource('custom_mine');
    await RuleDownloaderService.syncAllFilters();
    expect(saved(), isFalse);
  });
}
