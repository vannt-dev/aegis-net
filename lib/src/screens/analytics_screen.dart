import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/theme_provider.dart';
import '../providers/vpn_provider.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final vpn = context.watch<VpnProvider>();
    final accent = theme.primaryAccent;

    final topBlocked = vpn.topBlockedDomains;
    final topAllowed = vpn.topAllowedDomains;
    final qpsHistory = vpn.qpsHistory;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
        title: const Text(
          'Detailed Analytics & Reports',
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Top Blocked Domains Header
          Text(
            'Top Blocked Ad Networks',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold, color: accent),
          ),
          const SizedBox(height: 12),
          if (topBlocked.isEmpty) _buildEmptyState('No blocked queries yet'),
          Column(
            children: topBlocked.map((item) {
              final domain = item['domain'].toString();
              final count = (item['count'] as num?)?.toInt() ?? 0;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.shield_rounded,
                            color: Colors.redAccent.shade200, size: 18),
                        const SizedBox(width: 10),
                        Text(domain,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$count blocked',
                        style: TextStyle(
                            color: Colors.redAccent.shade200,
                            fontWeight: FontWeight.bold,
                            fontSize: 11),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 20),

          // Top Allowed / Requested Domains
          Text(
            'Top Requested Domains',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold, color: accent),
          ),
          const SizedBox(height: 12),
          if (topAllowed.isEmpty) _buildEmptyState('No resolved queries yet'),
          Column(
            children: topAllowed.map((item) {
              final domain = item['domain'].toString();
              final count = (item['count'] as num?)?.toInt() ?? 0;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle_outline_rounded,
                            color: Color(0xFF10B981), size: 18),
                        const SizedBox(width: 10),
                        Text(domain,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$count queries',
                        style: const TextStyle(
                            color: Color(0xFF10B981),
                            fontWeight: FontWeight.bold,
                            fontSize: 11),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 24),

          // Recent query rate.
          //
          // This was labelled "Hourly Query Distribution" over seven hardcoded
          // bars (12, 25, 18, 42, 68, 55, 84) that never changed. There is no
          // hourly bucketing in the engine to draw, so the chart now shows the
          // series that does exist — the queries-per-sample history the
          // provider already tracks — under a title that describes it.
          Text(
            'Recent Query Rate',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold, color: accent),
          ),
          const SizedBox(height: 12),
          Container(
            height: 180,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: qpsHistory.isEmpty
                ? Center(
                    child: Text(
                      'No traffic recorded yet',
                      style:
                          TextStyle(color: Colors.grey.shade500, fontSize: 13),
                    ),
                  )
                : BarChart(
                    BarChartData(
                      gridData: const FlGridData(show: false),
                      titlesData: const FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      barGroups: [
                        for (var i = 0; i < qpsHistory.length; i++)
                          BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(toY: qpsHistory[i], color: accent)
                            ],
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// Shown instead of a list the engine has no data for yet. The alternative —
  /// filling the gap with plausible-looking sample domains — reads on screen
  /// exactly like a real measurement.
  Widget _buildEmptyState(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Icon(Icons.hourglass_empty_rounded,
              color: Colors.grey.shade600, size: 18),
          const SizedBox(width: 10),
          Text(
            message,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
