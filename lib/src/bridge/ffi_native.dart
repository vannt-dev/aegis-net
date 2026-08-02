import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// Native FFI Function Signatures
typedef AegisInitC = Int32 Function();
typedef AegisInitDart = int Function();

typedef AegisLoadRulesC = Uint32 Function(
    Pointer<Utf8> rulesText, Int32 categoryId);
typedef AegisLoadRulesDart = int Function(
    Pointer<Utf8> rulesText, int categoryId);

typedef AegisAddDomainC = Void Function(Pointer<Utf8> domain);
typedef AegisAddDomainDart = void Function(Pointer<Utf8> domain);

typedef AegisIsBlockedC = Int32 Function(Pointer<Utf8> domain);
typedef AegisIsBlockedDart = int Function(Pointer<Utf8> domain);

typedef AegisSetCategoryC = Void Function(Int32 categoryId, Int32 enabled);
typedef AegisSetCategoryDart = void Function(int categoryId, int enabled);

typedef AegisSetUpstreamDnsC = Void Function(Pointer<Utf8> upstream);
typedef AegisSetUpstreamDnsDart = void Function(Pointer<Utf8> upstream);

typedef AegisGetStatsC = Pointer<Utf8> Function();
typedef AegisGetStatsDart = Pointer<Utf8> Function();

typedef AegisGetLogsC = Pointer<Utf8> Function(Int32 limit);
typedef AegisGetLogsDart = Pointer<Utf8> Function(int limit);

typedef AegisFreeStringC = Void Function(Pointer<Utf8> str);
typedef AegisFreeStringDart = void Function(Pointer<Utf8> str);

// Cross-process snapshots (iOS: app <-> PacketTunnel extension).
typedef AegisSnapshotC = Int32 Function(Pointer<Utf8> path);
typedef AegisSnapshotDart = int Function(Pointer<Utf8> path);

typedef AegisLoadRulesFileC = Uint32 Function(
    Pointer<Utf8> path, Int32 categoryId);
typedef AegisLoadRulesFileDart = int Function(
    Pointer<Utf8> path, int categoryId);

class AegisNativeBindings {
  static DynamicLibrary? _lib;
  static bool _isLoaded = false;

  static AegisInitDart? _init;
  static AegisLoadRulesDart? _loadRules;
  static AegisAddDomainDart? _addWhitelist;
  static AegisAddDomainDart? _addBlacklist;
  static AegisAddDomainDart? _removeWhitelist;
  static AegisAddDomainDart? _removeBlacklist;
  static AegisIsBlockedDart? _isDomainBlocked;
  static AegisSetCategoryDart? _setCategory;
  static AegisSetUpstreamDnsDart? _setUpstreamDns;
  static AegisGetStatsDart? _getStatsJson;
  static AegisGetLogsDart? _getRecentLogsJson;
  static AegisFreeStringDart? _freeString;
  static AegisSnapshotDart? _exportSettings;
  static AegisSnapshotDart? _importSettings;
  static AegisSnapshotDart? _exportStats;
  static AegisSnapshotDart? _importStats;
  static AegisLoadRulesFileDart? _loadRulesFile;

  /// Load native Aegis Core shared library
  static bool initNativeLibrary() {
    if (_isLoaded) return true;

    try {
      if (Platform.isAndroid) {
        _lib = DynamicLibrary.open('libaegis_core.so');
      } else if (Platform.isIOS || Platform.isMacOS) {
        _lib = DynamicLibrary.process();
      } else if (Platform.isWindows) {
        _lib = DynamicLibrary.open('aegis_core.dll');
      } else if (Platform.isLinux) {
        _lib = DynamicLibrary.open('libaegis_core.so');
      }

      if (_lib != null) {
        _init = _lib!.lookupFunction<AegisInitC, AegisInitDart>('aegis_init');
        _loadRules = _lib!.lookupFunction<AegisLoadRulesC, AegisLoadRulesDart>(
            'aegis_load_rules');
        _addWhitelist = _lib!
            .lookupFunction<AegisAddDomainC, AegisAddDomainDart>(
                'aegis_add_whitelist');
        _addBlacklist = _lib!
            .lookupFunction<AegisAddDomainC, AegisAddDomainDart>(
                'aegis_add_blacklist');
        _removeWhitelist = _lib!
            .lookupFunction<AegisAddDomainC, AegisAddDomainDart>(
                'aegis_remove_whitelist');
        _removeBlacklist = _lib!
            .lookupFunction<AegisAddDomainC, AegisAddDomainDart>(
                'aegis_remove_blacklist');
        _isDomainBlocked = _lib!
            .lookupFunction<AegisIsBlockedC, AegisIsBlockedDart>(
                'aegis_is_domain_blocked');
        _setCategory = _lib!
            .lookupFunction<AegisSetCategoryC, AegisSetCategoryDart>(
                'aegis_set_category');
        _setUpstreamDns = _lib!
            .lookupFunction<AegisSetUpstreamDnsC, AegisSetUpstreamDnsDart>(
                'aegis_set_upstream_dns');
        _getStatsJson = _lib!.lookupFunction<AegisGetStatsC, AegisGetStatsDart>(
            'aegis_get_stats_json');
        _getRecentLogsJson = _lib!
            .lookupFunction<AegisGetLogsC, AegisGetLogsDart>(
                'aegis_get_recent_logs_json');
        _freeString = _lib!
            .lookupFunction<AegisFreeStringC, AegisFreeStringDart>(
                'aegis_free_string');
        _exportSettings = _lib!
            .lookupFunction<AegisSnapshotC, AegisSnapshotDart>(
                'aegis_export_settings');
        _importSettings = _lib!
            .lookupFunction<AegisSnapshotC, AegisSnapshotDart>(
                'aegis_import_settings');
        _exportStats = _lib!.lookupFunction<AegisSnapshotC, AegisSnapshotDart>(
            'aegis_export_stats');
        _importStats = _lib!.lookupFunction<AegisSnapshotC, AegisSnapshotDart>(
            'aegis_import_stats');
        _loadRulesFile = _lib!
            .lookupFunction<AegisLoadRulesFileC, AegisLoadRulesFileDart>(
                'aegis_load_rules_file');

        _init?.call();
        _isLoaded = true;
        return true;
      }
    } catch (e) {
      _isLoaded = false;
    }
    return false;
  }

  static int loadRules(String rulesText, int categoryId) {
    if (!_isLoaded || _loadRules == null) return 0;
    final ptr = rulesText.toNativeUtf8();
    final count = _loadRules!(ptr, categoryId);
    malloc.free(ptr);
    return count;
  }

  static void addWhitelist(String domain) {
    if (!_isLoaded || _addWhitelist == null) return;
    final ptr = domain.toNativeUtf8();
    _addWhitelist!(ptr);
    malloc.free(ptr);
  }

  static void addBlacklist(String domain) {
    if (!_isLoaded || _addBlacklist == null) return;
    final ptr = domain.toNativeUtf8();
    _addBlacklist!(ptr);
    malloc.free(ptr);
  }

  static void removeWhitelist(String domain) {
    if (!_isLoaded || _removeWhitelist == null) return;
    final ptr = domain.toNativeUtf8();
    _removeWhitelist!(ptr);
    malloc.free(ptr);
  }

  static void removeBlacklist(String domain) {
    if (!_isLoaded || _removeBlacklist == null) return;
    final ptr = domain.toNativeUtf8();
    _removeBlacklist!(ptr);
    malloc.free(ptr);
  }

  static void setCategory(int categoryId, bool enabled) {
    if (!_isLoaded || _setCategory == null) return;
    _setCategory!(categoryId, enabled ? 1 : 0);
  }

  static void setUpstreamDns(String upstream) {
    if (!_isLoaded || _setUpstreamDns == null) return;
    final ptr = upstream.toNativeUtf8();
    _setUpstreamDns!(ptr);
    malloc.free(ptr);
  }

  static bool isDomainBlocked(String domain) {
    if (!_isLoaded || _isDomainBlocked == null) return false;
    final ptr = domain.toNativeUtf8();
    final res = _isDomainBlocked!(ptr);
    malloc.free(ptr);
    return res == 1;
  }

  /// 0 on success, negative on failure (see shared_state::SnapshotError).
  static int _snapshotCall(AegisSnapshotDart? fn, String path) {
    if (!_isLoaded || fn == null) return -1;
    final ptr = path.toNativeUtf8();
    final status = fn(ptr);
    malloc.free(ptr);
    return status;
  }

  static int exportSettings(String path) =>
      _snapshotCall(_exportSettings, path);

  static int importSettings(String path) =>
      _snapshotCall(_importSettings, path);

  static int exportStats(String path) => _snapshotCall(_exportStats, path);

  static int importStats(String path) => _snapshotCall(_importStats, path);

  static int loadRulesFile(String path, int categoryId) {
    if (!_isLoaded || _loadRulesFile == null) return 0;
    final ptr = path.toNativeUtf8();
    final count = _loadRulesFile!(ptr, categoryId);
    malloc.free(ptr);
    return count;
  }

  static String? getStatsJson() {
    if (!_isLoaded || _getStatsJson == null || _freeString == null) return null;
    final ptr = _getStatsJson!();
    if (ptr == nullptr) return null;
    final str = ptr.toDartString();
    _freeString!(ptr);
    return str;
  }

  static String? getRecentLogsJson(int limit) {
    if (!_isLoaded || _getRecentLogsJson == null || _freeString == null) {
      return null;
    }
    final ptr = _getRecentLogsJson!(limit);
    if (ptr == nullptr) return null;
    final str = ptr.toDartString();
    _freeString!(ptr);
    return str;
  }
}
