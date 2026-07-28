import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../bridge/aegis_bridge.dart';

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
  int _activeRulesCount = 128450;
  String _upstreamDns = 'Cloudflare (1.1.1.1)';

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
    DnsLogItem(
        id: '4',
        domain: 'clients3.google.com',
        isBlocked: false,
        timestamp: DateTime.now().subtract(const Duration(seconds: 35))),
    DnsLogItem(
        id: '5',
        domain: 'adservice.google.com',
        isBlocked: true,
        timestamp: DateTime.now().subtract(const Duration(seconds: 50))),
  ];

  final List<String> _whitelist = ['mybank.com', 'workplace.com'];
  final List<String> _blacklist = ['bad-tracker.net', 'crypto-miner.org'];

  Timer? _simulationTimer;

  bool get isVpnActive => _isVpnActive;
  bool get isConnecting => _isConnecting;
  int get activeRulesCount => _activeRulesCount;
  String get upstreamDns => _upstreamDns;
  Map<String, dynamic> get stats => _stats;
  List<DnsLogItem> get logs => List.unmodifiable(_logs);
  List<String> get whitelist => List.unmodifiable(_whitelist);
  List<String> get blacklist => List.unmodifiable(_blacklist);

  VpnProvider() {
    AegisBridge.initEngine();
  }

  Future<void> toggleVpn() async {
    _isConnecting = true;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 800));

    if (_isVpnActive) {
      await AegisBridge.stopVpn();
      _isVpnActive = false;
      _stopSimulation();
    } else {
      await AegisBridge.startVpn();
      _isVpnActive = true;
      _startSimulation();
    }

    _isConnecting = false;
    notifyListeners();
  }

  void setUpstreamDns(String provider) {
    _upstreamDns = provider;
    notifyListeners();
  }

  void addWhitelistDomain(String domain) {
    if (domain.trim().isEmpty) return;
    final clean = domain.trim().toLowerCase();
    if (!_whitelist.contains(clean)) {
      _whitelist.add(clean);
      AegisBridge.addWhitelist(clean);
      notifyListeners();
    }
  }

  void removeWhitelistDomain(String domain) {
    _whitelist.remove(domain);
    notifyListeners();
  }

  void addBlacklistDomain(String domain) {
    if (domain.trim().isEmpty) return;
    final clean = domain.trim().toLowerCase();
    if (!_blacklist.contains(clean)) {
      _blacklist.add(clean);
      AegisBridge.addBlacklist(clean);
      notifyListeners();
    }
  }

  void removeBlacklistDomain(String domain) {
    _blacklist.remove(domain);
    notifyListeners();
  }

  void _startSimulation() {
    _simulationTimer?.cancel();
    final random = Random();
    final sampleDomains = [
      'ads.google.com',
      'api.flutter.dev',
      'analytics.facebook.com',
      'pub.dev',
      'doubleclick.net',
      'cloudflare.com',
      'telemetry.applovin.com',
      'github.com',
      'tracking.vungle.com',
      'stackoverflow.com'
    ];

    _simulationTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!_isVpnActive) return;

      final domain = sampleDomains[random.nextInt(sampleDomains.length)];
      final isBlocked = AegisBridge.isDomainBlocked(domain);

      AegisBridge.recordQuery(domain, isBlocked);
      _stats = AegisBridge.getStats();

      _logs.insert(
        0,
        DnsLogItem(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          domain: domain,
          isBlocked: isBlocked,
          timestamp: DateTime.now(),
        ),
      );

      if (_logs.length > 100) {
        _logs.removeLast();
      }

      notifyListeners();
    });
  }

  void _stopSimulation() {
    _simulationTimer?.cancel();
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    super.dispose();
  }
}
