/// Web / Stub implementation when dart:ffi is unavailable
class AegisNativeBindings {
  static bool initNativeLibrary() => false;
  static int loadRules(String rulesText, int categoryId) => 0;
  static void addWhitelist(String domain) {}
  static void addBlacklist(String domain) {}
  static void removeWhitelist(String domain) {}
  static void removeBlacklist(String domain) {}
  static void setCategory(int categoryId, bool enabled) {}
  static void setUpstreamDns(String upstream) {}
  static bool isDomainBlocked(String domain) => false;
  static String? getStatsJson() => null;

  // Cross-process snapshots. -1 mirrors the native "no engine" status.
  static int exportSettings(String path) => -1;
  static int importSettings(String path) => -1;
  static int exportStats(String path) => -1;
  static int importStats(String path) => -1;
  static int loadRulesFile(String path, int categoryId) => 0;
}
