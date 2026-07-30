/// Web / Stub implementation when dart:ffi is unavailable
class AegisNativeBindings {
  static bool initNativeLibrary() => false;
  static int loadRules(String rulesText) => 0;
  static void addWhitelist(String domain) {}
  static void addBlacklist(String domain) {}
  static void removeWhitelist(String domain) {}
  static void removeBlacklist(String domain) {}
  static void setCategory(int categoryId, bool enabled) {}
  static bool isDomainBlocked(String domain) => false;
  static String? getStatsJson() => null;
}
