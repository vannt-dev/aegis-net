import 'dart:convert';
import 'dart:io';
import '../bridge/aegis_bridge.dart';

class FilterSource {
  final String id;
  final String name;
  final String url;
  final String description;
  bool isEnabled;

  FilterSource({
    required this.id,
    required this.name,
    required this.url,
    required this.description,
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
    for (final source in defaultSources) {
      if (source.isEnabled) {
        final content = await fetchFilterContent(source.url);
        if (content != null && content.isNotEmpty) {
          final count = AegisBridge.loadRulesText(content);
          totalLoaded += count;
        }
      }
    }
    return totalLoaded;
  }
}
