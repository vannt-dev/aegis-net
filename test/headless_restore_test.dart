import 'dart:io';

import 'package:aegis_net/src/bridge/aegis_bridge.dart';
import 'package:aegis_net/src/services/headless_restore.dart';
import 'package:aegis_net/src/services/rule_downloader_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The tunnel can start with no screen at all: Always-on VPN at boot, a Quick
/// Settings tap with the app closed, or the system restarting the service.
/// The engine starts empty in a new process, so such a start filtered with the
/// built-in seed rules alone until someone opened the app. The tunnel service
/// now runs [restoreEngineWithoutUi] in an engine of its own; these tests pin
/// that it puts the user's saved settings and lists back, and always says when
/// it is finished so the service can shut that engine down.
void main() {
  late Directory dir;
  late Map<String, String> served;
  late Map<int, bool> categories;

  String urlOf(String id) =>
      RuleDownloaderService.allSources.firstWhere((s) => s.id == id).url;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'disabled_filter_sources': ['hagezi_multi', 'stevenblack_porn'],
      'blacklist': ['my-own-block.example'],
      'block_adult': true,
    });
    dir = await Directory.systemTemp.createTemp('aegis_headless_');
    RuleDownloaderService.cacheDirForTest = dir;
    await RuleDownloaderService.loadSources();
    served = {
      for (final s in RuleDownloaderService.allSources)
        s.url: '${s.id}.example\n',
      urlOf('urlhaus'): 'malware-only.example\n',
    };
    RuleDownloaderService.fetcher = (url) async => served[url];
    categories = {};
    AegisBridge.debugSetCategoryOverride = (id, on) => categories[id] = on;
    AegisBridge.clearDownloadedRules();
  });

  tearDown(() async {
    AegisBridge.debugSetCategoryOverride = null;
    RuleDownloaderService.fetcher = RuleDownloaderService.fetchFilterContent;
    RuleDownloaderService.cacheDirForTest = null;
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('puts saved lists and settings back, without the network', () async {
    await RuleDownloaderService.syncAllFilters();
    AegisBridge.clearDownloadedRules(); // a new process
    served.clear(); // offline

    var doneCalls = 0;
    await restoreEngineWithoutUi(done: () async => doneCalls++);

    expect(AegisBridge.isDomainBlocked('malware-only.example'), isTrue);
    expect(AegisBridge.isDomainBlocked('my-own-block.example'), isTrue);
    expect(categories[3], isTrue, reason: 'Adult was switched on');
    expect(doneCalls, 1);
  });

  test('downloads missing lists before saying it is done', () async {
    // Never synced: the engine this runs in is shut down at "done", so a
    // download still running then would be lost.
    var doneCalls = 0;
    await restoreEngineWithoutUi(done: () async => doneCalls++);

    expect(AegisBridge.isDomainBlocked('malware-only.example'), isTrue);
    expect(await RuleDownloaderService.needsSync(), isFalse);
    expect(doneCalls, 1);
  });

  test('says it is done even when every download fails', () async {
    served.clear();
    var doneCalls = 0;
    await restoreEngineWithoutUi(
      done: () async => doneCalls++,
      waitBeforeRetry: () async {},
    );

    expect(AegisBridge.isDomainBlocked('my-own-block.example'), isTrue);
    expect(doneCalls, 1);
  });

  test('tries the downloads once more when the network was not up yet',
      () async {
    // At boot Always-on brings the tunnel up before the network is ready,
    // so the first round of downloads fails on every list.
    final later = Map.of(served);
    served.clear();
    var rounds = 0;
    RuleDownloaderService.fetcher = (url) async {
      if (url == urlOf('urlhaus')) rounds++;
      return served[url];
    };

    await restoreEngineWithoutUi(
      done: () async {},
      waitBeforeRetry: () async => served.addAll(later), // network is up
    );

    expect(rounds, 2);
    expect(AegisBridge.isDomainBlocked('malware-only.example'), isTrue);
  });
}
