/// Web build of the desktop resolver: there is none. A browser tab cannot bind
/// a UDP socket, so this exists only so callers compile — the API always
/// reports "not running", which is the truth on web.
class DesktopProxyStatus {
  const DesktopProxyStatus({required this.running, this.port, this.error});

  final bool running;
  final int? port;
  final String? error;

  bool get usableAsSystemResolver => false;
}

class DesktopDnsProxy {
  static const List<int> defaultPorts = [];

  static bool get isRunning => false;

  static int? get port => null;

  static Future<DesktopProxyStatus> start({
    List<int> ports = defaultPorts,
  }) async =>
      const DesktopProxyStatus(
        running: false,
        error: 'the web build has no local resolver',
      );

  static Future<void> stop() async {}
}
