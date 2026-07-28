/// Web / Stub implementation when dart:ffi is unavailable
class AegisNativeBindings {
  static bool initNativeLibrary() => false;
  static int loadRules(String rulesText) => 0;
  static void addWhitelist(String domain) {}
  static void addBlacklist(String domain) {}
  static bool isDomainBlocked(String domain) => false;
  static String? getStatsJson() => null;
}
