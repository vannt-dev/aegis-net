import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../bridge/aegis_bridge.dart';

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
    ),
  ];

  static List<FilterSource> _customSources = [];

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
  static Future<void> _applyDisabledState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final disabled =
          (prefs.getStringList('disabled_filter_sources') ?? []).toSet();
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
      final client = HttpClient();
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

    for (final source in allSources) {
      if (source.isEnabled) {
        final content = await fetchFilterContent(source.url);
        if (content != null && content.isNotEmpty) {
          final count = AegisBridge.loadRulesText(content);
          totalLoaded += count;
          (byCategory[source.categoryId] ??= StringBuffer())
            ..writeln(content)
            ..writeln();
        }
      }
    }

    await _publishToSharedContainer(byCategory);
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
