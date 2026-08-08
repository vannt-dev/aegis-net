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
      'custom_hosts': prefs.getStringList('custom_hosts') ?? [],
      'schedule_enabled': prefs.getBool('schedule_enabled') ?? false,
      'quiet_hours_start': prefs.getInt('quiet_hours_start') ?? 22,
      'quiet_hours_end': prefs.getInt('quiet_hours_end') ?? 6,
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

      if (data['custom_hosts'] is List) {
        final list = (data['custom_hosts'] as List).cast<String>();
        await prefs.setStringList('custom_hosts', list);
        for (final item in list) {
          final parts = item.split('=');
          if (parts.length == 2) {
            AegisBridge.addCustomHost(parts[0], parts[1]);
          }
        }
      }

      if (data['schedule_enabled'] is bool) {
        await prefs.setBool(
            'schedule_enabled', data['schedule_enabled'] as bool);
      }
      if (data['quiet_hours_start'] is int) {
        await prefs.setInt(
            'quiet_hours_start', data['quiet_hours_start'] as int);
      }
      if (data['quiet_hours_end'] is int) {
        await prefs.setInt('quiet_hours_end', data['quiet_hours_end'] as int);
      }

      return true;
    } catch (_) {
      return false;
    }
  }
}
