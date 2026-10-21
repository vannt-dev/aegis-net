/// One day of the history the engine keeps across restarts.
class DayStat {
  /// Local calendar day, at midnight.
  final DateTime date;
  final int total;
  final int blocked;

  /// Most-blocked domains that day as (domain, count), highest first.
  final List<MapEntry<String, int>> topBlocked;

  const DayStat({
    required this.date,
    required this.total,
    required this.blocked,
    this.topBlocked = const [],
  });

  int get allowed => total - blocked < 0 ? 0 : total - blocked;

  /// One element of the engine's history JSON, where `day` counts local days
  /// since 1970-01-01. Null for an element that does not parse.
  static DayStat? fromEngine(Object? raw) {
    if (raw is! Map) return null;
    final day = (raw['day'] as num?)?.toInt();
    if (day == null) return null;
    final utc = DateTime.utc(1970, 1, 1).add(Duration(days: day));
    final top = raw['top_blocked'];
    return DayStat(
      date: DateTime(utc.year, utc.month, utc.day),
      total: (raw['total'] as num?)?.toInt() ?? 0,
      blocked: (raw['blocked'] as num?)?.toInt() ?? 0,
      topBlocked: [
        if (top is List)
          for (final e in top.whereType<Map>())
            MapEntry(e['domain']?.toString() ?? '',
                (e['count'] as num?)?.toInt() ?? 0),
      ],
    );
  }

  /// The engine's history JSON, newest day first.
  static List<DayStat> listFromEngine(Object? raw) {
    if (raw is! List) return const [];
    final days = [
      for (final e in raw)
        if (fromEngine(e) case final DayStat day) day,
    ]..sort((a, b) => b.date.compareTo(a.date));
    return days;
  }

  /// Every day from the oldest in [newestFirst] to the newest, oldest first,
  /// with days that had no traffic at all filled in as zero so a chart's bars
  /// line up with dates.
  static List<DayStat> withGapsFilled(List<DayStat> newestFirst) {
    if (newestFirst.isEmpty) return const [];
    final byDate = {for (final d in newestFirst) d.date: d};
    final first = newestFirst.last.date;
    final last = newestFirst.first.date;
    final days = <DayStat>[];
    for (var d = first;
        !d.isAfter(last);
        d = DateTime(d.year, d.month, d.day + 1)) {
      days.add(byDate[d] ?? DayStat(date: d, total: 0, blocked: 0));
    }
    return days;
  }
}
