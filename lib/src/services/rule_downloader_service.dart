import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../bridge/aegis_bridge.dart';
import '../i18n/app_strings.dart';
import 'download_roots.dart';

class FilterSource {
  final String id;
  final String name;
  final String url;
  final String description;

  /// Rule category this list feeds (0: Ads, 1: Trackers, 2: Malware, 3: Adult).
  final int categoryId;
  bool isEnabled;

  FilterSource({
    required this.id,
    required this.name,
    required this.url,
    required this.description,
    this.categoryId = 0,
    this.isEnabled = true,
  });

  /// Display name in the current language.
  ///
  /// The preset lists carry a translation under `src_<id>_name`; a list the
  /// user subscribed to themselves has none, and falls back to what they typed.
  String get localizedName => AppStrings.maybe('src_${id}_name') ?? name;

  String get localizedDescription =>
      AppStrings.maybe('src_${id}_desc') ?? description;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'description': description,
        'categoryId': categoryId,
        'isEnabled': isEnabled,
      };

  factory FilterSource.fromJson(Map<String, dynamic> json) => FilterSource(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Custom List',
        url: json['url'] as String? ?? '',
        description: json['description'] as String? ?? 'User custom blocklist',
        categoryId: json['categoryId'] as int? ?? 0,
        isEnabled: json['isEnabled'] as bool? ?? true,
      );
}

class RuleDownloaderService {
  static final List<FilterSource> defaultSources = [
    FilterSource(
      id: 'adguard_dns',
      name: 'AdGuard DNS Filter',
      url: 'https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt',
      description: 'Official AdGuard DNS filter for mobile apps and trackers.',
    ),
    FilterSource(
      id: 'stevenblack',
      name: 'StevenBlack Unified Hosts',
      url: 'https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts',
      description: 'Consolidated host file blocking adservers and malware.',
    ),
    // Small and entirely hostname-based, so every line survives the DNS
    // parser — measured at 3,525 rules and zero unusable entries. uBlock
    // Origin Lite enables this one by default too.
    FilterSource(
      id: 'pgl_yoyo',
      name: "Peter Lowe's Ad and Tracking Server List",
      url:
          'https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext',
      description:
          'Hand-curated ad and tracking servers. Small, low false positives.',
      // Feeds the Trackers category, which otherwise has no list behind it at
      // all. Nearly everything here is also in the ad lists, so turning
      // Trackers off does not unblock much — DNS blocklists do not split
      // cleanly into "ads" and "trackers", and this is the honest half of that.
      categoryId: 1,
    ),
    // Mostly redundant against the three lists above — 93.5% of its 56,747
    // domains are already covered — but the 3,673 it does add cost only
    // 0.2 MB in the trie, so it earns its place. The full OISD list is
    // deliberately not here: it adds 11.1 MB, which the iOS PacketTunnel
    // extension cannot spare. Add that one as a custom source if you want it.
    FilterSource(
      id: 'oisd_small',
      name: 'OISD Small',
      url: 'https://small.oisd.nl/',
      description:
          'Curated aggregate of ad and tracking domains, tuned to avoid '
          'breaking sites.',
    ),
    // HaGeZi Multi NORMAL, off by default. 176,107 domains, 90,107 of them not
    // in the lists above, for +6.2 MB in the Ads trie (20.7 -> 26.9 MB). That
    // is more than the adult list (4.3 MB), which is off for the same reason,
    // so it stays opt-in. PRO adds 8.2 MB and the Threat Intelligence Feeds
    // mini list 9.2 MB, too close to the 11.1 MB that kept full OISD out.
    // The list data is GPL-3.0 and is only ever downloaded, never bundled.
    FilterSource(
      id: 'hagezi_multi',
      name: 'HaGeZi Multi NORMAL',
      url:
          'https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/multi.txt',
      description: 'Large all-round list of ad, tracking and other unwanted '
          'domains. Blocks more; adds about 6 MB of memory.',
      isEnabled: false,
    ),
    // Malware. About 1,900 hostnames, so the category costs next to nothing
    // to make real. It used to hold three invented domains (crypto-miner.org
    // and friends) and protected against nothing. abuse.ch retired its own
    // hosts file (410 Gone), so the URLhaus data now comes as the hosts list
    // the malware-filter project builds from it twice a day. The id stays
    // `urlhaus` so a saved on/off choice still applies.
    FilterSource(
      id: 'urlhaus',
      name: 'URLhaus Malware Hosts',
      url: 'https://curbengh.github.io/malware-filter/urlhaus-filter-hosts.txt',
      description: 'abuse.ch URLhaus hosts serving malware, as listed by the '
          'malware-filter project.',
      categoryId: 2,
    ),
    // Adult. Off by default, and deliberately not downloaded until it is
    // switched on: 76,751 hostnames cost 4.3 MB in the trie, which is real
    // money against the iOS PacketTunnel budget, and the Adult category is
    // disabled by default anyway.
    FilterSource(
      id: 'stevenblack_porn',
      name: 'StevenBlack Adult Hosts',
      url:
          'https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/porn-only/hosts',
      description: 'Adult sites only. Enable to make the Adult filter do '
          'anything; adds about 4 MB of memory.',
      categoryId: 3,
      isEnabled: false,
    ),
  ];

  static List<FilterSource> _customSources = [];

  /// Where each downloaded list is kept between runs, one file per source.
  /// Null (web, iOS, desktop, or before [initCache]) means nothing is kept.
  ///
  /// The engine holds rules in memory only, so without this every restart of
  /// the app (an update, a reboot, the system killing it) left the phone
  /// filtering with the built-in seed rules alone until someone tapped Sync.
  static Directory? _cacheDir;

  @visibleForTesting
  static set cacheDirForTest(Directory? dir) => _cacheDir = dir;

  /// Whether lists are kept on this platform (see [initCache]).
  static bool get keepsLists => _cacheDir != null;

  /// When the last sync that downloaded at least one list finished, in ms
  /// since the epoch.
  static const String prefLastSync = 'filter_lists_last_sync_ms';

  /// Lists older than this are downloaded again at start.
  static const Duration syncEvery = Duration(hours: 24);

  /// Downloads a list's text, or null when it could not be fetched.
  @visibleForTesting
  static Future<String?> Function(String url) fetcher = fetchFilterContent;

  /// Find the directory the lists are kept in. Android only: iOS reloads the
  /// per-category files its tunnel extension reads (see
  /// [_publishToSharedContainer]).
  static Future<void> initCache() async {
    if (_cacheDir != null) return;
    final filesDir = await AegisBridge.filesDirPath();
    if (filesDir == null) return;
    _cacheDir = Directory('$filesDir/filter_lists');
  }

  static File? _cacheFile(String sourceId) {
    final dir = _cacheDir;
    if (dir == null) return null;
    // Custom source ids are generated, but keep the name a plain file name
    // whatever they contain.
    final safe = sourceId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${dir.path}/$safe.txt');
  }

  static Future<String?> _readCache(String sourceId) async {
    final file = _cacheFile(sourceId);
    if (file == null) return null;
    try {
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      return content.isEmpty ? null : content;
    } catch (e) {
      debugPrint('[AegisRules] could not read saved list $sourceId: $e');
      return null;
    }
  }

  static Future<void> _writeCache(String sourceId, String content) async {
    final file = _cacheFile(sourceId);
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      // Write beside the old copy and swap, so a crash mid-write cannot
      // leave half a list behind.
      final partial = File('${file.path}.part');
      await partial.writeAsString(content, flush: true);
      await partial.rename(file.path);
    } catch (e) {
      debugPrint('[AegisRules] could not save list $sourceId: $e');
    }
  }

  /// Delete saved copies of sources that no longer exist (a removed custom
  /// list), so they do not sit on the phone forever.
  static Future<void> _pruneCache() async {
    final dir = _cacheDir;
    if (dir == null || !await dir.exists()) return;
    // Compared by file name: the listing's separators need not match the
    // ones the paths were built with.
    final keep =
        allSources.map((s) => _cacheFile(s.id)!.uri.pathSegments.last).toSet();
    try {
      await for (final entry in dir.list()) {
        if (entry is File && !keep.contains(entry.uri.pathSegments.last)) {
          await entry.delete();
        }
      }
    } catch (e) {
      debugPrint('[AegisRules] could not tidy saved lists: $e');
    }
  }

  /// Put the lists saved by the last sync back into the engine, without the
  /// network. Returns how many rules were loaded; 0 when nothing was saved,
  /// in which case the engine is left as it is (a tunnel that outlived the
  /// screen may still hold the rules of an earlier sync).
  static Future<int> loadCachedFilters() async {
    await loadSources();
    if (_cacheDir == null) return 0;

    final saved = <FilterSource, String>{};
    for (final source in allSources) {
      if (!source.isEnabled) continue;
      final content = await _readCache(source.id);
      if (content != null) saved[source] = content;
    }
    if (saved.isEmpty) return 0;

    AegisBridge.clearDownloadedRules();
    var total = 0;
    saved.forEach((source, content) {
      total += AegisBridge.loadRulesText(
        content,
        categoryId: source.categoryId,
        listId: source.id,
      );
    });
    return total;
  }

  /// Whether the lists should be downloaded again: never synced, last synced
  /// more than [syncEvery] ago, or a switched-on list has no saved copy yet.
  static Future<bool> needsSync() async {
    await loadSources();
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(prefLastSync);
    if (last == null) return true;
    final age =
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(last));
    if (age > syncEvery || age.isNegative) return true;
    if (_cacheDir == null) return false;
    for (final source in allSources) {
      if (source.isEnabled && await _readCache(source.id) == null) return true;
    }
    return false;
  }

  static List<FilterSource> get allSources =>
      [...defaultSources, ..._customSources];

  /// Load custom filter sources from SharedPreferences.
  ///
  /// One unparseable entry must not cost the user the rest of their lists, so
  /// entries are decoded individually and bad ones are dropped.
  static Future<void> loadCustomSources() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = prefs.getStringList('custom_filter_sources') ?? [];

      _customSources = [];
      for (final entry in jsonList) {
        try {
          final decoded = jsonDecode(entry);
          if (decoded is Map<String, dynamic>) {
            _customSources.add(FilterSource.fromJson(decoded));
          }
        } catch (e) {
          debugPrint('[AegisRules] dropping unreadable filter source: $e');
        }
      }
    } catch (e) {
      debugPrint('[AegisRules] could not read custom filter sources: $e');
    }
  }

  /// Add a custom filter list URL. Returns false if the same URL is already
  /// subscribed — downloading a list twice just doubles the work and reports
  /// an inflated rule count.
  static Future<bool> addCustomSource(FilterSource source) async {
    final normalised = source.url.trim().toLowerCase();
    final alreadyKnown = allSources
        .any((existing) => existing.url.trim().toLowerCase() == normalised);
    if (alreadyKnown) return false;

    _customSources.add(source);
    return _saveCustomSources();
  }

  /// Remove a custom filter list URL
  static Future<bool> removeCustomSource(String id) async {
    _customSources.removeWhere((s) => s.id == id);
    return _saveCustomSources();
  }

  /// Turn a source on or off and remember it. Preset sources are held in a
  /// const list, so their toggle is persisted by id rather than on the object.
  static Future<bool> setSourceEnabled(String id, bool enabled) async {
    for (final source in allSources) {
      if (source.id == id) source.isEnabled = enabled;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final disabled =
          allSources.where((s) => !s.isEnabled).map((s) => s.id).toList();
      await prefs.setStringList('disabled_filter_sources', disabled);
    } catch (e) {
      debugPrint('[AegisRules] could not persist source toggle: $e');
      return false;
    }

    return _saveCustomSources();
  }

  /// Re-apply persisted on/off state to every known source.
  ///
  /// The key stores the ids that are *off*, so an absent key and "nothing is
  /// off" look identical unless null is handled separately. Treating a missing
  /// key as an empty list switched every source on, which quietly overrode any
  /// source declared `isEnabled: false` — the adult list would have downloaded
  /// itself on first launch and spent 4.3 MB on a category that is off by
  /// default. Until the user touches a toggle, the declared defaults stand.
  static Future<void> _applyDisabledState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('disabled_filter_sources');
      if (saved == null) return;

      final disabled = saved.toSet();
      for (final source in allSources) {
        source.isEnabled = !disabled.contains(source.id);
      }
    } catch (e) {
      debugPrint('[AegisRules] could not read source toggles: $e');
    }
  }

  /// Load custom sources and their on/off state together. This is what the UI
  /// and [syncAllFilters] should call; [loadCustomSources] alone leaves every
  /// source at its default enabled state.
  static Future<void> loadSources() async {
    await loadCustomSources();
    await _applyDisabledState();
  }

  static Future<bool> _saveCustomSources() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList =
          _customSources.map((s) => jsonEncode(s.toJson())).toList();
      return await prefs.setStringList('custom_filter_sources', jsonList);
    } catch (e) {
      debugPrint('[AegisRules] could not save custom filter sources: $e');
      return false;
    }
  }

  /// Download filter list content from HTTP URL
  static Future<String?> fetchFilterContent(String url) async {
    try {
      final client = HttpClient(context: downloadSecurityContext());
      client.connectionTimeout = const Duration(seconds: 10);
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode == 200) {
        final content = await response.transform(utf8.decoder).join();
        return content;
      }
    } catch (e) {
      debugPrint('[AegisRules] filter download failed for $url: $e');
    }
    return null;
  }

  /// Download all enabled filter lists (default + custom) and update Rust Engine
  static Future<int> syncAllFilters() async {
    await loadSources();

    // Loading a list only inserts, so a source the user switched off would
    // keep blocking until the process restarted. Start from the built-in
    // seeds each sync; the user's own lists are not touched.
    AegisBridge.clearDownloadedRules();

    int totalLoaded = 0;
    // Category id -> concatenated list text, kept so the iOS tunnel extension
    // can reload the same rules in its own process.
    final byCategory = <int, StringBuffer>{};

    var downloaded = 0;
    for (final source in allSources) {
      if (source.isEnabled) {
        var content = await fetcher(source.url);
        if (content != null && content.isNotEmpty) {
          downloaded++;
          await _writeCache(source.id, content);
        } else {
          // A list host that is down today must not cost the user the list:
          // fall back to the copy from the last sync that worked.
          content = await _readCache(source.id);
        }
        if (content != null && content.isNotEmpty) {
          // Without the category the engine takes the default, 0, and every
          // list lands in Ads no matter what the source says. That is what
          // left the Trackers, Malware and Adult switches with nothing but
          // seed rules behind them; `categoryId` was only ever reaching the
          // per-category files written for the iOS extension below.
          final count = AegisBridge.loadRulesText(
            content,
            categoryId: source.categoryId,
            listId: source.id,
          );
          totalLoaded += count;
          (byCategory[source.categoryId] ??= StringBuffer())
            ..writeln(content)
            ..writeln();
        }
      }
    }

    await _publishToSharedContainer(byCategory);
    // Offline, every download fails: leave the sync due so the next start
    // tries again instead of waiting a day.
    if (downloaded > 0) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(prefLastSync, DateTime.now().millisecondsSinceEpoch);
    }
    await _pruneCache();
    return totalLoaded;
  }

  /// Filter lists run to hundreds of thousands of lines, so they are handed to
  /// the extension as plain text files rather than through a snapshot.
  static Future<void> _publishToSharedContainer(
      Map<int, StringBuffer> byCategory) async {
    final container = AegisBridge.sharedContainerPath;
    if (container == null) return;

    var wrote = false;
    // Every category, not just the ones with content: a category whose last
    // source was switched off has to have its file removed, or the extension
    // keeps loading the rules from the previous sync forever.
    for (var categoryId = 0; categoryId <= 3; categoryId++) {
      final content = byCategory[categoryId]?.toString() ?? '';
      final file =
          File('$container/${AegisBridge.rulesFileNameFor(categoryId)}');
      try {
        if (content.isEmpty) {
          if (await file.exists()) {
            await file.delete();
            wrote = true;
          }
          continue;
        }
        await file.writeAsString(content, flush: true);
        wrote = true;
      } catch (e) {
        // A container write failure must not fail the sync; the app's own
        // engine already has the rules.
        debugPrint('[AegisRules] could not publish category $categoryId: $e');
      }
    }

    // Filter lists bypass the settings snapshot, so nothing else would tell a
    // running tunnel that new rules are on disk.
    if (wrote) {
      AegisBridge.notifyTunnelReload();
    }
  }
}
