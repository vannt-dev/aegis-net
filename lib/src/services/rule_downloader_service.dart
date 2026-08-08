import 'dart:convert';
import 'dart:io';
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
  ];

  static List<FilterSource> _customSources = [];

  static List<FilterSource> get allSources =>
      [...defaultSources, ..._customSources];

  /// Load custom filter sources from SharedPreferences
  static Future<void> loadCustomSources() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = prefs.getStringList('custom_filter_sources') ?? [];
      _customSources = jsonList
          .map((s) =>
              FilterSource.fromJson(jsonDecode(s) as Map<String, dynamic>))
          .toList();
    } catch (_) {}
  }

  /// Add a custom filter list URL
  static Future<bool> addCustomSource(FilterSource source) async {
    _customSources.add(source);
    return _saveCustomSources();
  }

  /// Remove a custom filter list URL
  static Future<bool> removeCustomSource(String id) async {
    _customSources.removeWhere((s) => s.id == id);
    return _saveCustomSources();
  }

  static Future<bool> _saveCustomSources() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList =
          _customSources.map((s) => jsonEncode(s.toJson())).toList();
      return await prefs.setStringList('custom_filter_sources', jsonList);
    } catch (_) {
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
      // Return null on failure
    }
    return null;
  }

  /// Download all enabled filter lists (default + custom) and update Rust Engine
  static Future<int> syncAllFilters() async {
    await loadCustomSources();
    int totalLoaded = 0;
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

  static Future<void> _publishToSharedContainer(
      Map<int, StringBuffer> byCategory) async {
    final container = AegisBridge.sharedContainerPath;
    if (container == null) return;

    var wrote = false;
    for (final entry in byCategory.entries) {
      try {
        final file =
            File('$container/${AegisBridge.rulesFileNameFor(entry.key)}');
        await file.writeAsString(entry.value.toString(), flush: true);
        wrote = true;
      } catch (_) {}
    }

    if (wrote) {
      AegisBridge.notifyTunnelReload();
    }
  }
}
