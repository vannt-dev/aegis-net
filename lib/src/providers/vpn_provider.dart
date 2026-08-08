import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../bridge/aegis_bridge.dart';
import '../services/rule_downloader_service.dart';

class DnsLogItem {
  final String id;
  final String domain;
  final bool isBlocked;
  final DateTime timestamp;

  DnsLogItem({
    required this.id,
    required this.domain,
    required this.isBlocked,
    required this.timestamp,
  });
}

class VpnProvider extends ChangeNotifier {
  bool _isVpnActive = false;
  bool _isConnecting = false;
  final int _activeRulesCount = 128450;
  String _upstreamDns = 'Cloudflare DoH (https://1.1.1.1/dns-query)';

  DateTime? _pausedUntil;
  Timer? _pauseTimer;
  Timer? _autoSyncTimer;

  bool _blockAds = true;
  bool _blockTrackers = true;
  bool _blockMalware = true;
  bool _blockAdult = false;

  bool _scheduleEnabled = false;
  int _quietHoursStart = 22;
  int _quietHoursEnd = 6;
  final Map<String, String> _customHosts = {};

  final List<String> _bypassApps = ['com.zing.zalo', 'com.vietcombank.mobile'];

  Map<String, dynamic> _stats = {
    'total_queries': 1420,
    'blocked_queries': 385,
    'allowed_queries': 1035,
    'block_rate_percentage': 27.1,
    'estimated_data_saved_bytes': 57750000,
  };

  final List<DnsLogItem> _logs = [
    DnsLogItem(
        id: '1',
        domain: 'pagead2.googlesyndication.com',
        isBlocked: true,
        timestamp: DateTime.now().subtract(const Duration(seconds: 5))),
    DnsLogItem(
        id: '2',
        domain: 'api.github.com',
        isBlocked: false,
        timestamp: DateTime.now().subtract(const Duration(seconds: 12))),
    DnsLogItem(
        id: '3',
        domain: 'graph.facebook.com',
        isBlocked: true,
        timestamp: DateTime.now().subtract(const Duration(seconds: 20))),
  ];

  final List<String> _whitelist = ['mybank.com', 'workplace.com'];
  final List<String> _blacklist = ['bad-tracker.net', 'crypto-miner.org'];

  Timer? _simulationTimer;
  final bool enableSimulation;

  final List<double> _qpsHistory = [15, 28, 42, 35, 50, 48, 62];
  double _lastTotalQueries = 0;

  bool get isVpnActive => _isVpnActive && !isPaused;
  bool get isConnecting => _isConnecting;

  bool get scheduleEnabled => _scheduleEnabled;
  int get quietHoursStart => _quietHoursStart;
  int get quietHoursEnd => _quietHoursEnd;
  Map<String, String> get customHosts => Map.unmodifiable(_customHosts);

  /// Reason the tunnel refused to start, or null when it is up / has never
  /// been asked. Cleared on the next successful start.
  String? get lastError => _lastError;
  String? _lastError;

  /// Consumed by the UI after it has shown the failure once, so the message
  /// does not reappear on every rebuild.
  void clearLastError() {
    if (_lastError == null) return;
    _lastError = null;
    notifyListeners();
  }

  /// True when the device is on strict Private DNS ("hostname" mode). Android's
  /// resolver then speaks DoT directly to that provider and ignores the DNS
  /// server the tunnel advertises, so the tunnel is up and filtering nothing —
  /// the user sees ads with a green shield and no error anywhere.
  ///
  /// Only strict mode bypasses us. "opportunistic" probes DoT against our own
  /// virtual resolver, gets no answer on 853, and falls back to cleartext.
  bool get privateDnsBypass => _privateDnsBypass;
  bool _privateDnsBypass = false;

  Future<void> _refreshPrivateDnsState() async {
    final diagnostics = await AegisBridge.getVpnDiagnostics();
    final mode = diagnostics['privateDnsMode'] as String?;
    final bypassed = mode == 'hostname';
    if (bypassed == _privateDnsBypass) return;
    _privateDnsBypass = bypassed;
    notifyListeners();
  }

  bool get isPaused =>
      _pausedUntil != null && DateTime.now().isBefore(_pausedUntil!);
  Duration get pauseRemaining =>
      isPaused ? _pausedUntil!.difference(DateTime.now()) : Duration.zero;

  int get activeRulesCount => _activeRulesCount;
  String get upstreamDns => _upstreamDns;
  Map<String, dynamic> get stats => _stats;
  List<double> get qpsHistory => List.unmodifiable(_qpsHistory);
  List<DnsLogItem> get logs => List.unmodifiable(_logs);
  List<String> get whitelist => List.unmodifiable(_whitelist);
  List<String> get blacklist => List.unmodifiable(_blacklist);
  List<String> get bypassApps => List.unmodifiable(_bypassApps);

  bool get blockAds => _blockAds;
  bool get blockTrackers => _blockTrackers;
  bool get blockMalware => _blockMalware;
  bool get blockAdult => _blockAdult;

  VpnProvider({this.enableSimulation = true}) {
    _initPreferences();
    _bootstrapEngine();
    _startAutoSyncScheduler();
  }

  /// Initialize the core engine, then push the persisted allow/deny lists into
  /// it so the UI and the rule engine agree on state from the first query.
  Future<void> _bootstrapEngine() async {
    await AegisBridge.initEngine();
    for (final domain in _whitelist) {
      AegisBridge.addWhitelist(domain);
    }
    for (final domain in _blacklist) {
      AegisBridge.addBlacklist(domain);
    }
    for (final entry in _customHosts.entries) {
      AegisBridge.addCustomHost(entry.key, entry.value);
    }
  }

  Future<void> _initPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _upstreamDns = prefs.getString('upstream_dns') ??
          'Cloudflare DoH (https://1.1.1.1/dns-query)';
      _blockAds = prefs.getBool('block_ads') ?? true;
      _blockTrackers = prefs.getBool('block_trackers') ?? true;
      _blockMalware = prefs.getBool('block_malware') ?? true;
      _blockAdult = prefs.getBool('block_adult') ?? false;

      _scheduleEnabled = prefs.getBool('schedule_enabled') ?? false;
      _quietHoursStart = prefs.getInt('quiet_hours_start') ?? 22;
      _quietHoursEnd = prefs.getInt('quiet_hours_end') ?? 6;

      final savedWhitelist = prefs.getStringList('whitelist');
      if (savedWhitelist != null) {
        _whitelist.clear();
        _whitelist.addAll(savedWhitelist);
      }

      final savedBlacklist = prefs.getStringList('blacklist');
      if (savedBlacklist != null) {
        _blacklist.clear();
        _blacklist.addAll(savedBlacklist);
      }

      final savedBypass = prefs.getStringList('bypass_apps');
      if (savedBypass != null) {
        _bypassApps.clear();
        _bypassApps.addAll(savedBypass);
      }

      final savedHosts = prefs.getStringList('custom_hosts');
      if (savedHosts != null) {
        _customHosts.clear();
        for (final item in savedHosts) {
          final parts = item.split('=');
          if (parts.length == 2) {
            _customHosts[parts[0]] = parts[1];
          }
        }
      }

      AegisBridge.setUpstreamDns(_dohTargetFrom(_upstreamDns));
      _evaluateSchedule();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _saveListPref(String key, List<String> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(key, list);
    } catch (_) {}
  }

  /// Pulls the raw host/IP/URL out of a display label like
  /// "Cloudflare (1.1.1.1)" or "Cloudflare DoH (https://1.1.1.1/dns-query)",
  /// which is what the engine's DoH client actually needs.
  String _dohTargetFrom(String provider) {
    final match = RegExp(r'\(([^)]+)\)').firstMatch(provider);
    return match?.group(1) ?? provider;
  }

  void _startAutoSyncScheduler() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(const Duration(hours: 24), (timer) async {
      if (_isVpnActive) {
        await RuleDownloaderService.syncAllFilters();
      }
    });
  }

  Future<void> toggleVpn() async {
    _isConnecting = true;
    _pausedUntil = null;
    _pauseTimer?.cancel();
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 100));

    // Only move the flag if the tunnel actually changed state. startVpn resolves
    // false when the user declines the system VPN consent dialog, and claiming
    // protection there would be a lie.
    if (_isVpnActive) {
      if (await AegisBridge.stopVpn()) {
        _isVpnActive = false;
        _privateDnsBypass = false;
        _stopSimulation();
      }
    } else {
      if (await AegisBridge.startVpn(bypassApps: _bypassApps)) {
        _isVpnActive = true;
        _lastError = null;
        // A tunnel that came up is not the same as a tunnel that sees traffic;
        // strict Private DNS routes around it entirely.
        await _refreshPrivateDnsState();
        if (enableSimulation) {
          _startSimulation();
        }
      } else {
        // Keep the native reason so the UI can explain the failure — a silent
        // no-op toggle is what made the MIUI breakage impossible to diagnose.
        _lastError = AegisBridge.lastVpnError ?? 'tunnel_refused';
      }
    }

    _isConnecting = false;
    notifyListeners();
  }

  Future<void> pauseProtection(Duration duration) async {
    _pauseTimer?.cancel();

    // Stop the tunnel first and only claim "paused" if it really stopped —
    // otherwise the UI would report paused while DNS is still being filtered.
    if (_isVpnActive) {
      final stopped = await AegisBridge.stopVpn();
      if (!stopped) {
        notifyListeners();
        return;
      }
    }

    _pausedUntil = DateTime.now().add(duration);
    _pauseTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (isPaused) {
        notifyListeners();
        return;
      }
      timer.cancel();
      // Bring the tunnel up BEFORE clearing the pause, so the UI never shows
      // "protected" during the gap where the tunnel is still down.
      await _restoreTunnelAfterPause();
      _pausedUntil = null;
      notifyListeners();
    });
    notifyListeners();
  }

  Future<void> resumeProtection() async {
    final wasPaused = isPaused;
    _pauseTimer?.cancel();
    // Restart the tunnel that pauseProtection stopped, before dropping the
    // paused flag — same reason as above.
    if (wasPaused) {
      await _restoreTunnelAfterPause();
    }
    _pausedUntil = null;
    notifyListeners();
  }

  /// Bring the tunnel back up after a pause. If it refuses to start, drop the
  /// active flag so the UI stops claiming protection the engine isn't giving.
  Future<void> _restoreTunnelAfterPause() async {
    if (!_isVpnActive) return;
    final started = await AegisBridge.startVpn(bypassApps: _bypassApps);
    if (!started) {
      _isVpnActive = false;
      _stopSimulation();
    }
  }

  void toggleCategory(int categoryId, bool value) async {
    if (categoryId == 0) _blockAds = value;
    if (categoryId == 1) _blockTrackers = value;
    if (categoryId == 2) _blockMalware = value;
    if (categoryId == 3) _blockAdult = value;

    // Apply the change to the native rule engine, not just the UI.
    AegisBridge.setCategory(categoryId, value);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('block_ads', _blockAds);
      await prefs.setBool('block_trackers', _blockTrackers);
      await prefs.setBool('block_malware', _blockMalware);
      await prefs.setBool('block_adult', _blockAdult);
    } catch (_) {}

    notifyListeners();
  }

  void setUpstreamDns(String provider) async {
    _upstreamDns = provider;
    AegisBridge.setUpstreamDns(_dohTargetFrom(provider));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('upstream_dns', provider);
    } catch (_) {}
    notifyListeners();
  }

  void addWhitelistDomain(String domain) {
    if (domain.trim().isEmpty) return;
    final clean = domain.trim().toLowerCase();
    if (!_whitelist.contains(clean)) {
      _whitelist.add(clean);
      AegisBridge.addWhitelist(clean);
      _saveListPref('whitelist', _whitelist);
      notifyListeners();
    }
  }

  void removeWhitelistDomain(String domain) {
    _whitelist.remove(domain);
    AegisBridge.removeWhitelist(domain);
    _saveListPref('whitelist', _whitelist);
    notifyListeners();
  }

  void addBlacklistDomain(String domain) {
    if (domain.trim().isEmpty) return;
    final clean = domain.trim().toLowerCase();
    if (!_blacklist.contains(clean)) {
      _blacklist.add(clean);
      AegisBridge.addBlacklist(clean);
      _saveListPref('blacklist', _blacklist);
      notifyListeners();
    }
  }

  void removeBlacklistDomain(String domain) {
    _blacklist.remove(domain);
    AegisBridge.removeBlacklist(domain);
    _saveListPref('blacklist', _blacklist);
    notifyListeners();
  }

  void addBypassApp(String packageName) {
    if (packageName.trim().isEmpty) return;
    final clean = packageName.trim();
    if (!_bypassApps.contains(clean)) {
      _bypassApps.add(clean);
      _saveListPref('bypass_apps', _bypassApps);
      notifyListeners();
    }
  }

  void removeBypassApp(String packageName) {
    _bypassApps.remove(packageName);
    _saveListPref('bypass_apps', _bypassApps);
    notifyListeners();
  }

  void setSchedule(
      {required bool enabled, int? startHour, int? endHour}) async {
    _scheduleEnabled = enabled;
    if (startHour != null) _quietHoursStart = startHour;
    if (endHour != null) _quietHoursEnd = endHour;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('schedule_enabled', _scheduleEnabled);
      await prefs.setInt('quiet_hours_start', _quietHoursStart);
      await prefs.setInt('quiet_hours_end', _quietHoursEnd);
    } catch (_) {}
    _evaluateSchedule();
    notifyListeners();
  }

  void _evaluateSchedule() {
    if (!_scheduleEnabled) return;
    final nowHour = DateTime.now().hour;
    bool isQuietHours = false;
    if (_quietHoursStart > _quietHoursEnd) {
      isQuietHours = nowHour >= _quietHoursStart || nowHour < _quietHoursEnd;
    } else {
      isQuietHours = nowHour >= _quietHoursStart && nowHour < _quietHoursEnd;
    }

    if (isQuietHours && !_blockAdult) {
      toggleCategory(3, true);
    }
  }

  void addCustomHost(String domain, String ip) {
    if (domain.trim().isEmpty || ip.trim().isEmpty) return;
    final cleanDomain = domain.trim().toLowerCase();
    final cleanIp = ip.trim();
    _customHosts[cleanDomain] = cleanIp;
    AegisBridge.addCustomHost(cleanDomain, cleanIp);
    _saveCustomHostsPref();
    notifyListeners();
  }

  void removeCustomHost(String domain) {
    final cleanDomain = domain.trim().toLowerCase();
    _customHosts.remove(cleanDomain);
    AegisBridge.removeCustomHost(cleanDomain);
    _saveCustomHostsPref();
    notifyListeners();
  }

  Future<void> _saveCustomHostsPref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list =
          _customHosts.entries.map((e) => '${e.key}=${e.value}').toList();
      await prefs.setStringList('custom_hosts', list);
    } catch (_) {}
  }

  void _startSimulation() {
    _simulationTimer?.cancel();

    _simulationTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!isVpnActive) return;

      _evaluateSchedule();

      // Read real DNS query logs from Rust native FFI
      final realLogs = AegisBridge.getRecentLogs(limit: 50);
      if (realLogs.isNotEmpty) {
        _logs.clear();
        for (final item in realLogs) {
          final tsSec = (item['timestamp'] as num?)?.toInt() ?? 0;
          _logs.add(
            DnsLogItem(
              id: (item['id'] ?? DateTime.now().millisecondsSinceEpoch)
                  .toString(),
              domain: (item['domain'] ?? '').toString(),
              isBlocked: item['blocked'] == true,
              timestamp: tsSec > 0
                  ? DateTime.fromMillisecondsSinceEpoch(tsSec * 1000)
                  : DateTime.now(),
            ),
          );
        }
      }

      _stats = AegisBridge.getStats();
      _updateQpsHistory();
      notifyListeners();
    });
  }

  void _updateQpsHistory() {
    final current = (_stats['total_queries'] as num?)?.toDouble() ?? 0.0;
    if (_lastTotalQueries > 0) {
      double delta = current - _lastTotalQueries;
      if (delta < 0) delta = 0;
      _qpsHistory.add(delta);
      if (_qpsHistory.length > 7) {
        _qpsHistory.removeAt(0);
      }
    }
    _lastTotalQueries = current;
  }

  void _stopSimulation() {
    _simulationTimer?.cancel();
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    _pauseTimer?.cancel();
    _autoSyncTimer?.cancel();
    super.dispose();
  }
}
