import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../bridge/aegis_bridge.dart';
import 'app_info.dart';
import '../services/rule_downloader_service.dart';

class DnsLogItem {
  final String id;
  final String domain;
  final bool isBlocked;
  final DateTime timestamp;

  /// The app that made the query, or [AppInfo.unknownUid].
  final int uid;

  DnsLogItem({
    required this.id,
    required this.domain,
    required this.isBlocked,
    required this.timestamp,
    this.uid = AppInfo.unknownUid,
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

  /// Scheduled parental controls. Bounds are minutes since midnight so a
  /// schedule can start at 22:30, which whole hours could not express.
  bool _scheduleEnabled = false;
  int _quietHoursStart = 22 * 60;
  int _quietHoursEnd = 6 * 60;

  /// What the Adult toggle was set to before the schedule forced it on, or
  /// null when the schedule is not currently enforcing.
  ///
  /// Without this the schedule is one-way: it switches Adult filtering on at
  /// 22:00 and nothing ever switches it back, so one night leaves the category
  /// on permanently. Persisted, because the app can be killed inside the
  /// window and reopened outside it.
  bool? _blockAdultBeforeSchedule;

  Timer? _scheduleTimer;

  final Map<String, String> _customHosts = {};

  /// Packages excluded from the tunnel. Empty until the user excludes one.
  ///
  /// This shipped containing `com.zing.zalo` and `com.vietcombank.mobile`, and
  /// the list is handed to `addDisallowedApplication()` when the tunnel is
  /// built. A banking app and a messaging app were therefore carved out of the
  /// VPN on every fresh install, by a default nobody chose, in an app whose
  /// whole promise is that traffic goes through it.
  final List<String> _bypassApps = [];

  /// Counters, zeroed until the engine reports its own.
  ///
  /// These were seeded with 1420 queries / 385 blocked / 27.1% / 55.1 MB, which
  /// is what the dashboard showed on a fresh install before the tunnel had ever
  /// run — invented numbers, indistinguishable on screen from a measurement.
  Map<String, dynamic> _stats = {
    'total_queries': 0,
    'blocked_queries': 0,
    'allowed_queries': 0,
    'block_rate_percentage': 0.0,
    'estimated_data_saved_bytes': 0,
  };

  /// Query log, empty until the engine records something. Previously seeded
  /// with three fabricated entries for the same reason as [_stats].
  final List<DnsLogItem> _logs = [];

  /// The user's own lists, empty until the user puts something in them.
  ///
  /// These shipped seeded with `mybank.com` / `workplace.com` and
  /// `bad-tracker.net` / `crypto-miner.org` — invented domains that a fresh
  /// install presented as rules the user had written. Worse than the fabricated
  /// statistics cleaned up in 1.1.0: an entry here is pushed into the engine,
  /// so the app really was whitelisting two names nobody chose.
  final List<String> _whitelist = [];
  final List<String> _blacklist = [];

  Timer? _simulationTimer;
  final bool enableSimulation;

  /// Queries-per-sample history driving the traffic chart. Starts empty; it was
  /// seeded with `[15, 28, 42, 35, 50, 48, 62]`, which drew a convincing
  /// traffic curve on a device that had never resolved anything.
  final List<double> _qpsHistory = [];
  double _lastTotalQueries = 0;

  bool get isVpnActive => _isVpnActive && !isPaused;
  bool get isConnecting => _isConnecting;

  bool get scheduleEnabled => _scheduleEnabled;

  /// Quiet-hours bounds as minutes since midnight.
  int get quietHoursStart => _quietHoursStart;
  int get quietHoursEnd => _quietHoursEnd;

  /// True while the schedule is actively forcing the Adult category on.
  bool get scheduleEnforcing => _blockAdultBeforeSchedule != null;

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
    final sdk = (diagnostics['sdkInt'] as num?)?.toInt() ?? 0;
    if (sdk != _androidSdkInt) {
      _androidSdkInt = sdk;
      notifyListeners();
    }
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

  /// Most-blocked domains the engine has seen, highest first.
  ///
  /// Empty until the engine has counted something. It used to fall back to a
  /// hand-written list — plausible domains with plausible counts — which is
  /// indistinguishable from real data on screen; an analytics view that
  /// invents numbers is worse than one that admits it has none.
  List<Map<String, dynamic>> get topBlockedDomains =>
      _domainCounts(_stats['top_blocked']);

  /// Most-resolved allowed domains, highest first. Empty until counted.
  List<Map<String, dynamic>> get topAllowedDomains =>
      _domainCounts(_stats['top_allowed']);

  /// Android SDK level from the diagnostics call; 0 off Android.
  int _androidSdkInt = 0;

  /// Per-app statistics exist only on Android.
  bool get showsPerAppUi => _androidSdkInt > 0;

  /// The platform names the app behind a query from Android 10 (API 29).
  bool get perAppSupported => _androidSdkInt >= 29;

  /// Apps with the most queries, highest first. Empty until counted.
  List<AppStat> get topApps {
    final raw = _stats['top_apps'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => AppStat(
              uid: (e['uid'] as num?)?.toInt() ?? AppInfo.unknownUid,
              total: (e['total'] as num?)?.toInt() ?? 0,
              blocked: (e['blocked'] as num?)?.toInt() ?? 0,
            ))
        .toList();
  }

  final Map<int, AppInfo> _appInfo = {};
  bool _resolvingApps = false;

  AppInfo appInfo(int uid) => _appInfo[uid] ?? AppInfo(uid: uid);

  /// Asks the platform for the names of UIDs seen for the first time.
  /// When each UID the platform could not name was last asked about.
  final Map<int, DateTime> _unnamedAskedAt = {};

  /// How long a UID the platform could not name waits before it is asked
  /// again; a package being replaced is unnamed only for a moment.
  static const Duration _unnamedRetry = Duration(minutes: 1);

  @visibleForTesting
  DateTime Function() debugNow = DateTime.now;

  Future<void> _resolveNewApps() async {
    if (_resolvingApps) return;
    final now = debugNow();
    final wanted = <int>{
      for (final app in topApps) app.uid,
      for (final log in _logs) log.uid,
    }..removeWhere((uid) {
        if (uid < 0 || _appInfo.containsKey(uid)) return true;
        final askedAt = _unnamedAskedAt[uid];
        return askedAt != null && now.difference(askedAt) < _unnamedRetry;
      });
    if (wanted.isEmpty) return;
    _resolvingApps = true;
    try {
      final names = await AegisBridge.resolveApps(wanted.toList()..sort());
      // A failed call says nothing about the apps; ask again next refresh.
      if (names == null) return;
      for (final uid in wanted) {
        final info = names[uid];
        if (info != null && (info.label != null || info.packageName != null)) {
          _appInfo[uid] = info;
          _unnamedAskedAt.remove(uid);
        } else {
          _unnamedAskedAt[uid] = now;
        }
      }
      notifyListeners();
    } finally {
      _resolvingApps = false;
    }
  }

  int? _logAppFilter;

  /// The app the query log is narrowed to, or null for every app.
  int? get logAppFilter => _logAppFilter;

  void setLogAppFilter(int? uid) {
    if (uid == _logAppFilter) return;
    _logAppFilter = uid;
    notifyListeners();
  }

  @visibleForTesting
  void debugSetStats(Map<String, dynamic> stats) {
    _stats = stats;
    notifyListeners();
  }

  @visibleForTesting
  void debugSetAppInfo(Map<int, AppInfo> apps) {
    _appInfo
      ..clear()
      ..addAll(apps);
    notifyListeners();
  }

  @visibleForTesting
  void debugSetAndroidSdk(int sdk) {
    _androidSdkInt = sdk;
    notifyListeners();
  }

  @visibleForTesting
  Future<void> debugResolveApps() => _resolveNewApps();

  List<Map<String, dynamic>> _domainCounts(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => {
              'domain': e['domain']?.toString() ?? 'unknown',
              'count': (e['count'] as num?)?.toInt() ?? 0,
            })
        .toList();
  }

  List<double> get qpsHistory => List.unmodifiable(_qpsHistory);
  List<DnsLogItem> get logs => List.unmodifiable(_logs);
  List<String> get whitelist => List.unmodifiable(_whitelist);
  List<String> get blacklist => List.unmodifiable(_blacklist);
  List<String> get bypassApps => List.unmodifiable(_bypassApps);

  bool get blockAds => _blockAds;
  bool get blockTrackers => _blockTrackers;
  bool get blockMalware => _blockMalware;
  bool get blockAdult => _blockAdult;

  /// Rule category ids, matching the Rust engine's `RuleCategory` ordering.
  static const int _adultCategoryId = 3;

  static const String _prefScheduleEnabled = 'schedule_enabled';
  static const String _prefQuietStart = 'quiet_hours_start_minutes';
  static const String _prefQuietEnd = 'quiet_hours_end_minutes';
  static const String _prefScheduleRestore = 'schedule_prior_block_adult';

  late final Future<void> _ready;

  /// Completes once persisted settings have been loaded into this object.
  ///
  /// Loading is asynchronous but the constructor is not, so anything that
  /// writes state has to wait for it — a setting changed while the load is
  /// still in flight would otherwise be overwritten by the stored value a
  /// moment later.
  Future<void> get ready => _ready;

  VpnProvider({this.enableSimulation = true}) {
    _ready = _initialize();
    _startAutoSyncScheduler();
    _startScheduleWatcher();
  }

  Future<void> _initialize() async {
    await _initPreferences();
    await _bootstrapEngine();
    // Last, so a window that ended while the app was closed hands the Adult
    // toggle back instead of leaving it forced on.
    await _evaluateSchedule();
    await _adoptRunningTunnel();
  }

  /// The tunnel can outlive the screen: leaving with Back ends the activity
  /// while the VPN service keeps running, and the provider built on return
  /// starts from "off". Take the service's word for it instead.
  Future<void> _adoptRunningTunnel() async {
    final diagnostics = await AegisBridge.getVpnDiagnostics();
    // A toggle made while this was loading has already settled the state.
    if (_isVpnActive || _isConnecting || diagnostics['tunnelUp'] != true) {
      return;
    }
    _isVpnActive = true;
    await _refreshPrivateDnsState();
    if (enableSimulation) {
      _startSimulation();
    }
    notifyListeners();
  }

  /// Initialize the core engine, then push the persisted allow/deny lists into
  /// it so the UI and the rule engine agree on state from the first query.
  Future<void> _bootstrapEngine() async {
    await AegisBridge.initEngine();
    // After initEngine: a native call made before it never reaches the engine.
    AegisBridge.setBlockDohHosts(_interceptHardcodedDns);
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

  /// Re-read everything from storage and push it back into the engine.
  ///
  /// Restoring a config backup writes SharedPreferences behind this object's
  /// back; without this the restore only takes effect on the next launch while
  /// the UI still shows the previous lists.
  Future<void> reloadFromPreferences() async {
    await _initPreferences();
    await _bootstrapEngine();
    notifyListeners();
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
      _interceptHardcodedDns = prefs.getBool('intercept_hardcoded_dns') ?? true;

      _scheduleEnabled = prefs.getBool(_prefScheduleEnabled) ?? false;
      // The bounds were whole hours before; migrate them once so an existing
      // 22:00 -> 06:00 schedule does not come back as 00:22 -> 00:06.
      _quietHoursStart = prefs.getInt(_prefQuietStart) ??
          (prefs.getInt('quiet_hours_start') ?? 22) * 60;
      _quietHoursEnd = prefs.getInt(_prefQuietEnd) ??
          (prefs.getInt('quiet_hours_end') ?? 6) * 60;
      _blockAdultBeforeSchedule = prefs.getBool(_prefScheduleRestore);

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
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _saveListPref(String key, List<String> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(key, list);
    } catch (_) {}
  }

  static final RegExp _dotUpstream = RegExp(
      r'^(?:tls|dot)://(?:\[[0-9A-Fa-f:.]+\]|[A-Za-z0-9.\-]+|[0-9A-Fa-f:]+)'
      r'(?::\d{1,5})?(?:#[A-Za-z0-9.\-]+)?/?$');

  /// Checks a resolver typed by the user and returns it trimmed, or null when
  /// it is not one the engine can use.
  ///
  /// Accepted: an `https://` DoH URL, or a DNS-over-TLS target written
  /// `tls://host[:port][#name]` (`dot://` works too). A bad value must be
  /// refused here: the engine answers every query SERVFAIL for an upstream it
  /// cannot reach, so saving a typo would take DNS down for the whole device.
  static String? normalizeCustomUpstream(String input) {
    final value = input.trim();
    if (value.isEmpty || value.contains(RegExp(r'\s'))) return null;
    if (value.startsWith('https://')) {
      final uri = Uri.tryParse(value);
      return uri != null && uri.host.isNotEmpty ? value : null;
    }
    return _dotUpstream.hasMatch(value) ? value : null;
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
      if (await AegisBridge.startVpn(
          bypassApps: _bypassApps,
          interceptHardcodedDns: _interceptHardcodedDns)) {
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
    final started = await AegisBridge.startVpn(
        bypassApps: _bypassApps, interceptHardcodedDns: _interceptHardcodedDns);
    if (!started) {
      _isVpnActive = false;
      _stopSimulation();
    }
  }

  void toggleCategory(int categoryId, bool value) async {
    await _applyCategory(categoryId, value);
    notifyListeners();
  }

  /// Push a category toggle to the engine and to storage.
  ///
  /// Split out from [toggleCategory] so the schedule can flip a category
  /// without the notify — it batches its own — while still going through one
  /// path that keeps the UI, the native engine, and prefs in agreement.
  Future<void> _applyCategory(int categoryId, bool value) async {
    if (categoryId == 0) _blockAds = value;
    if (categoryId == 1) _blockTrackers = value;
    if (categoryId == 2) _blockMalware = value;
    if (categoryId == _adultCategoryId) _blockAdult = value;

    // Apply the change to the native rule engine, not just the UI.
    AegisBridge.setCategory(categoryId, value);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('block_ads', _blockAds);
      await prefs.setBool('block_trackers', _blockTrackers);
      await prefs.setBool('block_malware', _blockMalware);
      await prefs.setBool('block_adult', _blockAdult);
    } catch (_) {}
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

  /// Always resolve [domain]: put it on the allow list and take it off the
  /// block list, so the two lists never disagree about one name.
  void allowDomain(String domain) {
    final clean = domain.trim().toLowerCase();
    if (clean.isEmpty) return;
    if (_blacklist.contains(clean)) removeBlacklistDomain(clean);
    addWhitelistDomain(clean);
  }

  /// Always block [domain]: the mirror image of [allowDomain].
  void blockDomain(String domain) {
    final clean = domain.trim().toLowerCase();
    if (clean.isEmpty) return;
    if (_whitelist.contains(clean)) removeWhitelistDomain(clean);
    addBlacklistDomain(clean);
  }

  /// Replaces the query log. The log normally comes from the native engine,
  /// which a widget test does not have.
  @visibleForTesting
  void debugSetLogs(List<DnsLogItem> logs) {
    _logs
      ..clear()
      ..addAll(logs);
    notifyListeners();
  }

  bool _interceptHardcodedDns = true;

  /// The "stop apps from bypassing the filter" switch.
  bool get interceptHardcodedDns => _interceptHardcodedDns;

  /// The "stop apps from bypassing the filter" switch. Host-name blocking
  /// applies at once; the resolver routes are fixed when the tunnel is
  /// built, so a running tunnel is rebuilt.
  Future<void> setInterceptHardcodedDns(bool enabled) async {
    if (enabled == _interceptHardcodedDns) return;
    _interceptHardcodedDns = enabled;
    AegisBridge.setBlockDohHosts(enabled);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('intercept_hardcoded_dns', enabled);
    } catch (_) {}

    // One rebuild at a time: a start sent while the previous tunnel is still
    // up is ignored by the service, which would leave it on the old value.
    final rebuild = _tunnelRebuild.then((_) => _rebuildTunnel());
    _tunnelRebuild = rebuild;
    await rebuild;
  }

  Future<void> _tunnelRebuild = Future.value();

  Future<void> _rebuildTunnel() async {
    // A paused tunnel picks the value up when the pause ends.
    if (!_isVpnActive || isPaused) return;
    if (!await AegisBridge.stopVpn()) return;
    final started = await AegisBridge.startVpn(
        bypassApps: _bypassApps, interceptHardcodedDns: _interceptHardcodedDns);
    if (!started) {
      _isVpnActive = false;
      _stopSimulation();
      _lastError = AegisBridge.lastVpnError ?? 'tunnel_refused';
    }
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

  /// Update the schedule. Bounds are minutes since midnight; pass null to
  /// leave one unchanged.
  Future<void> setSchedule({
    required bool enabled,
    int? startMinutes,
    int? endMinutes,
  }) async {
    await _ready;
    _scheduleEnabled = enabled;
    if (startMinutes != null) _quietHoursStart = startMinutes % (24 * 60);
    if (endMinutes != null) _quietHoursEnd = endMinutes % (24 * 60);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefScheduleEnabled, _scheduleEnabled);
      await prefs.setInt(_prefQuietStart, _quietHoursStart);
      await prefs.setInt(_prefQuietEnd, _quietHoursEnd);
    } catch (_) {}

    await _evaluateSchedule();
    notifyListeners();
  }

  /// True when `now` falls inside the quiet-hours window.
  bool isWithinQuietHours(DateTime now) {
    final minutes = now.hour * 60 + now.minute;
    if (_quietHoursStart == _quietHoursEnd) return false;
    if (_quietHoursStart < _quietHoursEnd) {
      return minutes >= _quietHoursStart && minutes < _quietHoursEnd;
    }
    // Overnight window, e.g. 22:00 -> 06:00.
    return minutes >= _quietHoursStart || minutes < _quietHoursEnd;
  }

  /// Force the Adult category on inside the window and hand the user's own
  /// setting back when the window ends.
  Future<void> _evaluateSchedule() async {
    final shouldEnforce =
        _scheduleEnabled && isWithinQuietHours(DateTime.now());

    if (shouldEnforce && _blockAdultBeforeSchedule == null) {
      _blockAdultBeforeSchedule = _blockAdult;
      await _persistScheduleRestorePoint();
      if (!_blockAdult) {
        await _applyCategory(_adultCategoryId, true);
      }
      notifyListeners();
      return;
    }

    if (!shouldEnforce && _blockAdultBeforeSchedule != null) {
      final restoreTo = _blockAdultBeforeSchedule!;
      _blockAdultBeforeSchedule = null;
      await _persistScheduleRestorePoint();
      if (_blockAdult != restoreTo) {
        await _applyCategory(_adultCategoryId, restoreTo);
      }
      notifyListeners();
    }
  }

  Future<void> _persistScheduleRestorePoint() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_blockAdultBeforeSchedule == null) {
        await prefs.remove(_prefScheduleRestore);
      } else {
        await prefs.setBool(_prefScheduleRestore, _blockAdultBeforeSchedule!);
      }
    } catch (_) {}
  }

  /// Re-check the window on a timer. The schedule has to advance whether or
  /// not the tunnel is up, so this does not ride along on the stats poll.
  void _startScheduleWatcher() {
    _scheduleTimer?.cancel();
    _scheduleTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      await _ready;
      await _evaluateSchedule();
    });
  }

  /// True if `value` is an IPv4 or IPv6 literal the engine can answer with.
  ///
  /// Kept here rather than using `InternetAddress.tryParse` so the check works
  /// on web too, where `dart:io` is unavailable.
  static bool isValidIpAddress(String value) {
    final ip = value.trim();
    if (ip.isEmpty) return false;

    if (ip.contains(':')) {
      // IPv6: hex groups, at most one `::` run, up to 8 groups.
      if (RegExp(r'[^0-9a-fA-F:]').hasMatch(ip)) return false;
      if (ip.split('::').length > 2) return false;
      final groups = ip.split(':').where((g) => g.isNotEmpty);
      if (groups.length > 8) return false;
      return groups.every((g) => g.length <= 4);
    }

    final octets = ip.split('.');
    if (octets.length != 4) return false;
    return octets.every((o) {
      if (o.isEmpty || o.length > 3) return false;
      final n = int.tryParse(o);
      return n != null && n >= 0 && n <= 255;
    });
  }

  /// Pin a domain to a fixed address. Returns false for input the engine
  /// would silently ignore, so the caller can say so instead of showing a
  /// mapping that never takes effect.
  bool addCustomHost(String domain, String ip) {
    final cleanDomain = domain.trim().toLowerCase();
    final cleanIp = ip.trim();
    if (cleanDomain.isEmpty || !isValidIpAddress(cleanIp)) return false;

    _customHosts[cleanDomain] = cleanIp;
    AegisBridge.addCustomHost(cleanDomain, cleanIp);
    _saveCustomHostsPref();
    notifyListeners();
    return true;
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
              uid: (item['uid'] as num?)?.toInt() ?? AppInfo.unknownUid,
            ),
          );
        }
      }

      _stats = AegisBridge.getStats();
      unawaited(_resolveNewApps());
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
    _scheduleTimer?.cancel();
    super.dispose();
  }
}
