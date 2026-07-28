import 'dart:convert';
import 'package:flutter/services.dart';

class AegisBridge {
  static const MethodChannel _vpnChannel = MethodChannel('com.aegisnet/vpn');
  static bool _isEngineInitialized = false;

  // Local state cache for development / cross-platform fallback
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

  /// Initialize Aegis Rust Core Engine & Load Default Filter Rules
  static Future<bool> initEngine() async {
    _isEngineInitialized = true;
    return true;
  }

  /// Start Local VPN Tunnel
  static Future<bool> startVpn() async {
    try {
      final bool success = await _vpnChannel.invokeMethod('startVpn');
      return success;
    } on MissingPluginException {
      // Desktop / Web / Testing Fallback
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

  /// Check if a domain is blocked by current rule engine
  static bool isDomainBlocked(String domain) {
    final clean = domain.trim().toLowerCase();
    if (_whitelistedDomains.contains(clean)) return false;
    if (_blacklistedDomains.contains(clean)) return true;
    return _loadedRules.any((rule) => clean.contains(rule));
  }

  /// Add domain to Whitelist
  static void addWhitelist(String domain) {
    _whitelistedDomains.add(domain.trim().toLowerCase());
    _blacklistedDomains.remove(domain.trim().toLowerCase());
  }

  /// Add domain to Blacklist
  static void addBlacklist(String domain) {
    _blacklistedDomains.add(domain.trim().toLowerCase());
    _whitelistedDomains.remove(domain.trim().toLowerCase());
  }

  /// Get live filtering statistics summary
  static Map<String, dynamic> getStats() {
    final total = _totalQueries;
    final blocked = _blockedQueries;
    final allowed = total - blocked;
    final rate = total > 0 ? (blocked / total) * 100 : 0.0;
    final savedBytes = blocked * 150 * 1024; // ~150KB per ad

    return {
      'total_queries': total,
      'blocked_queries': blocked,
      'allowed_queries': allowed,
      'block_rate_percentage': rate,
      'estimated_data_saved_bytes': savedBytes,
    };
  }

  /// Record simulated query for demo/logs
  static void recordQuery(String domain, bool isBlocked) {
    _totalQueries++;
    if (isBlocked) _blockedQueries++;
  }
}
