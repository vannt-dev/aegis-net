import 'dart:async';
import 'dart:io';

class DnsPingResult {
  final String name;
  final String ip;
  final int latencyMs;
  final bool isFastest;

  DnsPingResult({
    required this.name,
    required this.ip,
    required this.latencyMs,
    this.isFastest = false,
  });
}

class DnsBenchmarkService {
  static final List<Map<String, String>> dnsProviders = [
    {'name': 'Cloudflare', 'ip': '1.1.1.1'},
    {'name': 'Google', 'ip': '8.8.8.8'},
    {'name': 'AdGuard DNS', 'ip': '94.140.14.14'},
    {'name': 'Quad9', 'ip': '9.9.9.9'},
    {'name': 'Control D', 'ip': '76.76.2.0'},
  ];

  /// Benchmark latency to all DNS providers in parallel
  static Future<List<DnsPingResult>> benchmarkAll() async {
    final List<Future<DnsPingResult>> futures =
        dnsProviders.map((provider) async {
      final name = provider['name']!;
      final ip = provider['ip']!;
      final latency = await measurePing(ip);
      return DnsPingResult(name: name, ip: ip, latencyMs: latency);
    }).toList();

    final results = await Future.wait(futures);
    results.sort((a, b) => a.latencyMs.compareTo(b.latencyMs));

    if (results.isNotEmpty) {
      final fastest = results.first;
      return results.map((r) {
        return DnsPingResult(
          name: r.name,
          ip: r.ip,
          latencyMs: r.latencyMs,
          isFastest: r.name == fastest.name,
        );
      }).toList();
    }

    return results;
  }

  /// Measure ping latency to a specific IP address
  static Future<int> measurePing(String ip) async {
    final stopwatch = Stopwatch()..start();
    try {
      final socket =
          await Socket.connect(ip, 53, timeout: const Duration(seconds: 2));
      socket.destroy();
      stopwatch.stop();
      return stopwatch.elapsedMilliseconds;
    } catch (_) {
      stopwatch.stop();
      return -1;
    }
  }
}
