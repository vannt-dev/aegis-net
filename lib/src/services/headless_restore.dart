import 'package:flutter/foundation.dart';

import '../providers/vpn_provider.dart';
import 'rule_downloader_service.dart';

Future<void> _waitForNetwork() => Future.delayed(const Duration(seconds: 30));

/// Fill the engine when the tunnel starts without the app's screen: Always-on
/// VPN at boot, a Quick Settings tap with the app closed, or the system
/// restarting the service.
///
/// The engine keeps its rules in memory and only the Dart side knows the saved
/// settings, so such a start used to filter with the built-in seed rules alone
/// until the app was opened. The tunnel service runs this in a Flutter engine
/// of its own and shuts that engine down once [done] has been called, which
/// happens whatever goes wrong here.
Future<void> restoreEngineWithoutUi({
  required Future<void> Function() done,
  @visibleForTesting Future<void> Function() waitBeforeRetry = _waitForNetwork,
}) async {
  VpnProvider? provider;
  try {
    // The same start-up the screen runs: saved settings, then the lists kept
    // from the last sync.
    provider = VpnProvider(enableSimulation: false);
    await provider.ready;
    // Lists missing or older than a day are downloaded again. Wait for that:
    // a download still running at [done] would be cut off.
    await provider.pendingListSync;
    // At boot the tunnel comes up before the network does, and every download
    // then fails. Try once more a little later.
    if (await RuleDownloaderService.needsSync()) {
      await waitBeforeRetry();
      await RuleDownloaderService.syncAllFilters();
    }
  } catch (e) {
    debugPrint('[AegisHeadless] restore failed: $e');
  } finally {
    provider?.dispose();
    await done();
  }
}
