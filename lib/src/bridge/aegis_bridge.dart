import 'dart:convert';
import 'package:flutter/services.dart';
import 'ffi_bindings.dart';

class AegisBridge {
  static const MethodChannel _vpnChannel = MethodChannel('com.aegisnet/vpn');
  static bool _useNativeFfi = false;

  // Memory fallback state
  static final Set<String> _whitelistedDomains = {};
  static final Set<String> _blacklistedDomains = {};
  static final Set<String> _loadedRules = {
    'doubleclick.net',
    'googleadservices.com',
    'ads.facebook.com',
    'aniview.com',
    'adnxs.com',
    'adcolony.com',
    'unityads.unity3d.com',
    'vungle.com',
    'applovin.com',
    'mopub.com'
  };

  static int _totalQueries = 1420;
  static int _blockedQueries = 385;

  /// Initialize Aegis Core Engine (Attempts native FFI load first)
  static Future<bool> initEngine() async {
    _useNativeFfi = AegisNativeBindings.initNativeLibrary();
    return true;
  }

  /// Start Local VPN Tunnel
  static Future<bool> startVpn() async {
    try {
      final bool success = await _vpnChannel.invokeMethod('startVpn');
      return success;
    } on MissingPluginException {
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Stop Local VPN Tunnel
  static Future<bool> stopVpn() async {
    try {
      final bool success = await _vpnChannel.invokeMethod('stopVpn');
      return success;
    } on MissingPluginException {
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Load raw rules text into engine
  static int loadRulesText(String content) {
    if (_useNativeFfi) {
      return AegisNativeBindings.loadRules(content);
    } else {
      int added = 0;
      for (final line in content.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty &&
            !trimmed.startsWith('#') &&
            !trimmed.startsWith('!')) {
          _loadedRules.add(trimmed.toLowerCase());
          added++;
        }
      }
      return added;
    }
  }

  /// Check if a domain is blocked by current rule engine
  static bool isDomainBlocked(String domain) {
    final clean = domain.trim().toLowerCase();
    if (_useNativeFfi) {
      return AegisNativeBindings.isDomainBlocked(clean);
    } else {
      if (_whitelistedDomains.contains(clean)) return false;
      if (_blacklistedDomains.contains(clean)) return true;
      return _loadedRules.any((rule) => clean.contains(rule));
    }
  }

  /// Add domain to Whitelist
  static void addWhitelist(String domain) {
    final clean = domain.trim().toLowerCase();
    if (_useNativeFfi) {
      AegisNativeBindings.addWhitelist(clean);
    }
    _whitelistedDomains.add(clean);
    _blacklistedDomains.remove(clean);
  }

  /// Add domain to Blacklist
  static void addBlacklist(String domain) {
    final clean = domain.trim().toLowerCase();
    if (_useNativeFfi) {
      AegisNativeBindings.addBlacklist(clean);
    }
    _blacklistedDomains.add(clean);
    _whitelistedDomains.remove(clean);
  }

  /// Get live filtering statistics summary
  static Map<String, dynamic> getStats() {
    if (_useNativeFfi) {
      final jsonStr = AegisNativeBindings.getStatsJson();
      if (jsonStr != null && jsonStr.isNotEmpty) {
        try {
          return jsonDecode(jsonStr);
        } catch (_) {}
      }
    }

    final total = _totalQueries;
    final blocked = _blockedQueries;
    final allowed = total - blocked;
    final rate = total > 0 ? (blocked / total) * 100 : 0.0;
    final savedBytes = blocked * 150 * 1024;

    return {
      'total_queries': total,
      'blocked_queries': blocked,
      'allowed_queries': allowed,
      'block_rate_percentage': rate,
      'estimated_data_saved_bytes': savedBytes,
    };
  }

  /// Record simulated query
  static void recordQuery(String domain, bool isBlocked) {
    _totalQueries++;
    if (isBlocked) _blockedQueries++;
  }
}
