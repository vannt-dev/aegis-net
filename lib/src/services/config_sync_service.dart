import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/network_rule.dart';

/// Export and restore the user's configuration as JSON.
///
/// This writes SharedPreferences directly, so a caller holding a live
/// [VpnProvider] has to ask it to re-read afterwards — otherwise the restore
/// lands on disk while the running app keeps showing the old lists.
class ConfigSyncService {
  /// Bumped when the exported shape changes. An import that does not recognise
  /// the version refuses the file rather than half-applying it.
  static const int formatVersion = 1;

  static Future<String> exportConfigToJson() async {
    final prefs = await SharedPreferences.getInstance();
    final map = <String, dynamic>{
      'version': formatVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'whitelist': prefs.getStringList('whitelist') ?? <String>[],
      'blacklist': prefs.getStringList('blacklist') ?? <String>[],
      'bypass_apps': prefs.getStringList('bypass_apps') ?? <String>[],
      'custom_filter_sources':
          prefs.getStringList('custom_filter_sources') ?? <String>[],
      'custom_hosts': prefs.getStringList('custom_hosts') ?? <String>[],
      'schedule_enabled': prefs.getBool('schedule_enabled') ?? false,
      'block_cname_trackers': prefs.getBool('block_cname_trackers') ?? true,
      'block_idn_domains': prefs.getBool('block_idn_domains') ?? false,
      prefNetworkScope:
          prefs.getString(prefNetworkScope) ?? NetworkScope.all.stored,
      prefSsidExceptionsOn: prefs.getBool(prefSsidExceptionsOn) ?? false,
      prefSsidExceptions: decodeSsids(prefs.getString(prefSsidExceptions)),
      // Minutes since midnight, matching what VpnProvider stores. Whole hours
      // could not express a schedule that starts at 22:30.
      'quiet_hours_start_minutes':
          prefs.getInt('quiet_hours_start_minutes') ?? 22 * 60,
      'quiet_hours_end_minutes':
          prefs.getInt('quiet_hours_end_minutes') ?? 6 * 60,
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// Restore a previously exported config. Returns false and changes nothing
  /// if the input is not a config this version understands.
  static Future<bool> importConfigFromJson(String jsonStr) async {
    final Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map<String, dynamic>) return false;
      data = decoded;
    } catch (_) {
      return false;
    }

    // Anything that parses as JSON would otherwise be accepted and applied as
    // an empty config, silently wiping the user's lists.
    if (data['version'] != formatVersion) return false;

    try {
      final prefs = await SharedPreferences.getInstance();

      await _restoreList(prefs, data, 'whitelist');
      await _restoreList(prefs, data, 'blacklist');
      await _restoreList(prefs, data, 'bypass_apps');
      await _restoreList(prefs, data, 'custom_filter_sources');
      await _restoreList(prefs, data, 'custom_hosts');

      if (data['block_cname_trackers'] is bool) {
        await prefs.setBool(
            'block_cname_trackers', data['block_cname_trackers'] as bool);
      }
      if (data['block_idn_domains'] is bool) {
        await prefs.setBool(
            'block_idn_domains', data['block_idn_domains'] as bool);
      }
      final scope = data[prefNetworkScope];
      if (scope is String &&
          NetworkScope.values.any((s) => s.stored == scope)) {
        await prefs.setString(prefNetworkScope, scope);
      }
      if (data[prefSsidExceptionsOn] is bool) {
        await prefs.setBool(
            prefSsidExceptionsOn, data[prefSsidExceptionsOn] as bool);
      }
      final ssids = data[prefSsidExceptions];
      if (ssids is List) {
        await prefs.setString(
            prefSsidExceptions,
            encodeSsids(ssids
                .whereType<String>()
                .map((n) => cleanSsid(n, exact: true))
                .whereType<String>()
                .toSet()));
      }
      if (data['schedule_enabled'] is bool) {
        await prefs.setBool(
            'schedule_enabled', data['schedule_enabled'] as bool);
      }
      await _restoreMinutes(prefs, data, 'quiet_hours_start_minutes');
      await _restoreMinutes(prefs, data, 'quiet_hours_end_minutes');

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Store a list of strings, skipping any entry that is not one. `cast` would
  /// throw halfway through instead, leaving the restore half-applied.
  static Future<void> _restoreList(
    SharedPreferences prefs,
    Map<String, dynamic> data,
    String key,
  ) async {
    final raw = data[key];
    if (raw is! List) return;
    await prefs.setStringList(key, raw.whereType<String>().toList());
  }

  static Future<void> _restoreMinutes(
    SharedPreferences prefs,
    Map<String, dynamic> data,
    String key,
  ) async {
    final value = data[key];
    if (value is! int || value < 0 || value >= 24 * 60) return;
    await prefs.setInt(key, value);
  }
}
