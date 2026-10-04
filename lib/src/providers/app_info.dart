import '../i18n/app_strings.dart';

/// What Android says about the app behind a UID in the per-app statistics.
class AppInfo {
  const AppInfo({
    required this.uid,
    this.packageName,
    this.label,
    this.isSystem = false,
    this.sharedCount = 0,
  });

  factory AppInfo.fromMap(Map<dynamic, dynamic> map) => AppInfo(
        uid: (map['uid'] as num?)?.toInt() ?? unknownUid,
        packageName: map['package'] as String?,
        label: map['label'] as String?,
        isSystem: map['isSystem'] == true,
        sharedCount: (map['sharedCount'] as num?)?.toInt() ?? 0,
      );

  /// Recorded when the platform cannot say which app asked.
  static const int unknownUid = -1;

  /// Below this, UIDs belong to the OS itself rather than to an installed app.
  static const int firstAppUid = 10000;

  final int uid;
  final String? packageName;
  final String? label;
  final bool isSystem;

  /// Other packages that share this UID, such as the many behind android.uid.system.
  final int sharedCount;

  String get displayName {
    if (uid == unknownUid) return AppStrings.get('app_unknown');
    final name = label ?? packageName;
    if (name != null) return sharedCount > 0 ? '$name (+$sharedCount)' : name;
    if (uid < firstAppUid) return AppStrings.get('app_system');
    return AppStrings.get('app_uid').replaceAll('%s', '$uid');
  }
}

/// One row of the engine's per-app tallies.
class AppStat {
  const AppStat(
      {required this.uid, required this.total, required this.blocked});

  final int uid;
  final int total;
  final int blocked;

  double get blockRate => total == 0 ? 0 : blocked / total;
}
