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

typedef AegisFreeStringC = Void Function(Pointer<Utf8> str);
typedef AegisFreeStringDart = void Function(Pointer<Utf8> str);

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
  static AegisFreeStringDart? _freeString;

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
        _freeString = _lib!
            .lookupFunction<AegisFreeStringC, AegisFreeStringDart>(
                'aegis_free_string');

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

  static String? getStatsJson() {
    if (!_isLoaded || _getStatsJson == null || _freeString == null) return null;
    final ptr = _getStatsJson!();
    if (ptr == nullptr) return null;
    final str = ptr.toDartString();
    _freeString!(ptr);
    return str;
  }
}
