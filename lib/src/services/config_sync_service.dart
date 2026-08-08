import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../bridge/aegis_bridge.dart';

class ConfigSyncService {
  static Future<String> exportConfigToJson() async {
    final prefs = await SharedPreferences.getInstance();
    final map = <String, dynamic>{
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'whitelist': prefs.getStringList('whitelist') ?? [],
      'blacklist': prefs.getStringList('blacklist') ?? [],
      'bypass_apps': prefs.getStringList('bypass_apps') ?? [],
      'custom_filter_sources':
          prefs.getStringList('custom_filter_sources') ?? [],
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  static Future<bool> importConfigFromJson(String jsonStr) async {
    try {
      final Map<String, dynamic> data = jsonDecode(jsonStr);
      final prefs = await SharedPreferences.getInstance();

      if (data['whitelist'] is List) {
        final list = (data['whitelist'] as List).cast<String>();
        await prefs.setStringList('whitelist', list);
        for (final item in list) {
          AegisBridge.addWhitelist(item);
        }
      }

      if (data['blacklist'] is List) {
        final list = (data['blacklist'] as List).cast<String>();
        await prefs.setStringList('blacklist', list);
        for (final item in list) {
          AegisBridge.addBlacklist(item);
        }
      }

      if (data['custom_filter_sources'] is List) {
        final list = (data['custom_filter_sources'] as List).cast<String>();
        await prefs.setStringList('custom_filter_sources', list);
      }

      return true;
    } catch (_) {
      return false;
    }
  }
}
