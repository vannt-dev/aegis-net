import 'dart:convert';
import 'dart:io';
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

  /// Download all enabled filter lists and update Rust Engine
  static Future<int> syncAllFilters() async {
    int totalLoaded = 0;
    // Category id -> concatenated list text, kept so the iOS tunnel extension
    // can reload the same rules in its own process.
    final byCategory = <int, StringBuffer>{};

    for (final source in defaultSources) {
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
    for (final entry in byCategory.entries) {
      try {
        final file =
            File('$container/${AegisBridge.rulesFileNameFor(entry.key)}');
        await file.writeAsString(entry.value.toString(), flush: true);
        wrote = true;
      } catch (_) {
        // A container write failure must not fail the sync; the app's own
        // engine already has the rules.
      }
    }

    // Filter lists bypass the settings snapshot, so nothing else would tell a
    // running tunnel that new rules are on disk.
    if (wrote) {
      AegisBridge.notifyTunnelReload();
    }
  }
}
