import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'ffi_bindings.dart';

class AegisBridge {
  static const MethodChannel _vpnChannel = MethodChannel('com.aegisnet/vpn');
  static bool _useNativeFfi = false;

  /// Android and iOS are the only platforms that ship a real tunnel. Everywhere
  /// else (web, desktop) the app runs as a demo with no native side, so a
  /// missing channel there is expected rather than a failure.
  static bool get _expectsNativeTunnel =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

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
      // On Android/iOS an absent channel means the native handler never
      // registered, so no tunnel is running. Reporting success here would make
      // the UI claim protection that does not exist.
      return !_expectsNativeTunnel;
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
      return !_expectsNativeTunnel;
    } catch (e) {
      return false;
    }
  }

  /// Load raw rules text into engine. [categoryId] follows the same mapping
  /// as [setCategory] (0: Ads, 1: Trackers, 2: Malware, 3: Adult); defaults to
  /// Ads since that's what every current caller loads.
  static int loadRulesText(String content, {int categoryId = 0}) {
    if (_useNativeFfi) {
      return AegisNativeBindings.loadRules(content, categoryId);
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
      if (_matchesRuleSet(_whitelistedDomains, clean)) return false;
      if (_matchesRuleSet(_blacklistedDomains, clean)) return true;
      return _matchesRuleSet(_loadedRules, clean);
    }
  }

  /// Returns true when [domain] equals a rule in [rules] or is a subdomain of
  /// one. Substring matching is deliberately avoided so that `myadnxs.com` is
  /// not caught by the rule `adnxs.com`.
  static bool _matchesRuleSet(Set<String> rules, String domain) {
    if (rules.contains(domain)) return true;
    return rules.any((rule) => domain.endsWith('.$rule'));
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

  /// Remove domain from Whitelist
  static void removeWhitelist(String domain) {
    final clean = domain.trim().toLowerCase();
    if (_useNativeFfi) {
      AegisNativeBindings.removeWhitelist(clean);
    }
    _whitelistedDomains.remove(clean);
  }

  /// Remove domain from Blacklist
  static void removeBlacklist(String domain) {
    final clean = domain.trim().toLowerCase();
    if (_useNativeFfi) {
      AegisNativeBindings.removeBlacklist(clean);
    }
    _blacklistedDomains.remove(clean);
  }

  /// Enable/disable a rule category on the engine.
  /// (0: Ads, 1: Trackers, 2: Malware, 3: Adult)
  static void setCategory(int categoryId, bool enabled) {
    if (_useNativeFfi) {
      AegisNativeBindings.setCategory(categoryId, enabled);
    }
  }

  /// Point the engine's upstream DoH resolver at a new host/IP/URL.
  static void setUpstreamDns(String upstream) {
    if (_useNativeFfi) {
      AegisNativeBindings.setUpstreamDns(upstream);
    }
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
