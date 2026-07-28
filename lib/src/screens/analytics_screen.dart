import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/theme_provider.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final accent = theme.primaryAccent;

    final topBlocked = [
      {'domain': 'doubleclick.net', 'count': 142},
      {'domain': 'graph.facebook.com', 'count': 98},
      {'domain': 'pagead2.googlesyndication.com', 'count': 76},
      {'domain': 'telemetry.applovin.com', 'count': 45},
      {'domain': 'aniview.com', 'count': 24},
    ];

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
          Column(
            children: topBlocked.map((item) {
              final domain = item['domain'] as String;
              final count = item['count'] as int;
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
                        color: Colors.red.withOpacity(0.15),
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

          const SizedBox(height: 24),

          // Hourly Activity Heatmap / Bar Chart
          Text(
            'Hourly Query Distribution',
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
            child: BarChart(
              BarChartData(
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                barGroups: [
                  BarChartGroupData(
                      x: 0, barRods: [BarChartRodData(toY: 12, color: accent)]),
                  BarChartGroupData(
                      x: 1, barRods: [BarChartRodData(toY: 25, color: accent)]),
                  BarChartGroupData(
                      x: 2, barRods: [BarChartRodData(toY: 18, color: accent)]),
                  BarChartGroupData(
                      x: 3, barRods: [BarChartRodData(toY: 42, color: accent)]),
                  BarChartGroupData(
                      x: 4, barRods: [BarChartRodData(toY: 68, color: accent)]),
                  BarChartGroupData(
                      x: 5, barRods: [BarChartRodData(toY: 55, color: accent)]),
                  BarChartGroupData(
                      x: 6, barRods: [BarChartRodData(toY: 84, color: accent)]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
