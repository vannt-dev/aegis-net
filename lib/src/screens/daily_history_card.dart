import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../i18n/app_strings.dart';
import '../providers/daily_history.dart';
import '../providers/vpn_provider.dart';

/// Queries and blocks per day for the last 30 days, kept across restarts: a
/// stacked bar per day, then the same numbers as a list with each day's
/// most-blocked domains.
class DailyHistoryCard extends StatefulWidget {
  const DailyHistoryCard({super.key, required this.accent});

  final Color accent;

  @override
  State<DailyHistoryCard> createState() => _DailyHistoryCardState();
}

class _DailyHistoryCardState extends State<DailyHistoryCard> {
  static const _blockedColor = Color(0xFFFF6B6B);

  @override
  void initState() {
    super.initState();
    // The provider re-reads the history only now and then; opening the
    // screen should show today as it is.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<VpnProvider>().refreshHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    final history = context.watch<VpnProvider>().dailyHistory;
    final accent = widget.accent;
    final title = Text(
      AppStrings.get('history_title'),
      style:
          TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: accent),
    );

    if (history.isEmpty) {
      return Column(
        key: const Key('daily_history_card'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          const SizedBox(height: 12),
          _box(Text(
            AppStrings.get('history_empty'),
            key: const Key('daily_history_empty'),
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          )),
        ],
      );
    }

    final days = DayStat.withGapsFilled(history);
    return Column(
      key: const Key('daily_history_card'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title,
        const SizedBox(height: 12),
        _box(Column(
          children: [
            SizedBox(height: 160, child: _chart(days, accent)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legend(accent, AppStrings.get('history_allowed')),
                const SizedBox(width: 16),
                _legend(_blockedColor, AppStrings.get('history_blocked')),
              ],
            ),
          ],
        )),
        const SizedBox(height: 8),
        for (final day in history) _dayRow(day),
      ],
    );
  }

  Widget _chart(List<DayStat> days, Color accent) {
    final label = DateFormat('d/M');
    return BarChart(
      BarChartData(
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        alignment: BarChartAlignment.spaceBetween,
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          topTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                // First, last and every seventh day: enough to read dates
                // off without labels colliding.
                final show = i == 0 ||
                    i == days.length - 1 ||
                    (days.length - 1 - i) % 7 == 0;
                if (!show || i < 0 || i >= days.length) {
                  return const SizedBox.shrink();
                }
                return Text(label.format(days[i].date),
                    style:
                        TextStyle(color: Colors.grey.shade500, fontSize: 10));
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF0D1117),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final day = days[group.x];
              return BarTooltipItem(
                '${_dateLabel(day.date)}\n${_counts(day)}',
                const TextStyle(color: Colors.white, fontSize: 11),
              );
            },
          ),
        ),
        barGroups: [
          for (var i = 0; i < days.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: days[i].total.toDouble(),
                  width: days.length > 20 ? 5 : 9,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(2)),
                  rodStackItems: [
                    BarChartRodStackItem(
                        0, days[i].blocked.toDouble(), _blockedColor),
                    BarChartRodStackItem(days[i].blocked.toDouble(),
                        days[i].total.toDouble(), accent),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _dayRow(DayStat day) {
    final top = day.topBlocked.take(3).map((e) => e.key).join(', ');
    return Container(
      key: Key('history_day_${DateFormat('yyyy-MM-dd').format(day.date)}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_dateLabel(day.date),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
              Text(_counts(day),
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
            ],
          ),
          if (top.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              AppStrings.get('history_top').replaceAll('%s', top),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  String _dateLabel(DateTime date) {
    final now = DateTime.now();
    if (date == DateTime(now.year, now.month, now.day)) {
      return AppStrings.get('history_today');
    }
    return DateFormat('d/M/yyyy').format(date);
  }

  static String _counts(DayStat day) => AppStrings.get('history_counts')
      .replaceAll('%total', '${day.total}')
      .replaceAll('%blocked', '${day.blocked}');

  static Widget _legend(Color color, String text) => Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 6),
          Text(text,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
        ],
      );

  static Widget _box(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: child,
      );
}
