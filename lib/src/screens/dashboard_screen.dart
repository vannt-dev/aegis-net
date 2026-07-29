import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/vpn_provider.dart';
import '../providers/theme_provider.dart';
import '../i18n/app_strings.dart';

const Color emeraldColor = Color(0xFF10B981);
const Color emeraldDarkColor = Color(0xFF065F46);

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VpnProvider>();
    final theme = context.watch<ThemeProvider>();
    final accent = theme.primaryAccent;
    final stats = vpn.stats;

    final int totalQueries = stats['total_queries'] ?? 0;
    final int blockedQueries = stats['blocked_queries'] ?? 0;
    final double blockRate =
        (stats['block_rate_percentage'] as num?)?.toDouble() ?? 0.0;
    final double dataSavedMb =
        ((stats['estimated_data_saved_bytes'] as num?)?.toDouble() ?? 0.0) /
            (1024 * 1024);

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Status
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppStrings.get('app_title'),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.0,
                          color: accent,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AppStrings.get('app_subtitle'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: vpn.isPaused
                          ? Colors.amber.shade900.withValues(alpha: 0.3)
                          : (vpn.isVpnActive
                              ? emeraldDarkColor.withValues(alpha: 0.4)
                              : Colors.red.shade900.withValues(alpha: 0.3)),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: vpn.isPaused
                            ? Colors.amberAccent
                            : (vpn.isVpnActive
                                ? emeraldColor
                                : Colors.redAccent),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: vpn.isPaused
                                ? Colors.amberAccent
                                : (vpn.isVpnActive
                                    ? emeraldColor
                                    : Colors.redAccent),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          vpn.isPaused
                              ? AppStrings.get('paused')
                              : (vpn.isVpnActive
                                  ? AppStrings.get('protected')
                                  : AppStrings.get('unprotected')),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: vpn.isPaused
                                ? Colors.amberAccent
                                : (vpn.isVpnActive
                                    ? emeraldColor
                                    : Colors.redAccent),
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Paused Banner if active
              if (vpn.isPaused)
                Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade900.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.amberAccent.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.timer_outlined,
                              color: Colors.amberAccent, size: 20),
                          const SizedBox(width: 10),
                          Text(
                            '${AppStrings.get("paused")} (${_formatDuration(vpn.pauseRemaining)})',
                            style: const TextStyle(
                                color: Colors.amberAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 13),
                          ),
                        ],
                      ),
                      TextButton(
                        onPressed: () => vpn.resumeProtection(),
                        child: Text(AppStrings.get('resume_now'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),

              // Glowing Interactive Power Toggle Button
              Center(
                child: GestureController(
                  onTap: vpn.isConnecting ? null : () => vpn.toggleVpn(),
                  isActive: vpn.isVpnActive,
                  isConnecting: vpn.isConnecting,
                  isPaused: vpn.isPaused,
                  accentColor: accent,
                ),
              ),

              const SizedBox(height: 24),

              // Quick Pause Options (5m, 15m, 1h)
              if (vpn.isVpnActive && !vpn.isPaused)
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('${AppStrings.get("pause")}: ',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12)),
                      _buildPauseChip(
                          context, vpn, '5m', const Duration(minutes: 5)),
                      const SizedBox(width: 6),
                      _buildPauseChip(
                          context, vpn, '15m', const Duration(minutes: 15)),
                      const SizedBox(width: 6),
                      _buildPauseChip(
                          context, vpn, '1h', const Duration(hours: 1)),
                    ],
                  ),
                ),

              const SizedBox(height: 28),

              // Stat Grid (2x2)
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 1.45,
                children: [
                  _buildStatCard(
                    title: AppStrings.get('total_queries'),
                    value: '$totalQueries',
                    icon: Icons.swap_vert_rounded,
                    color: accent,
                  ),
                  _buildStatCard(
                    title: AppStrings.get('ads_blocked'),
                    value: '$blockedQueries',
                    icon: Icons.shield_outlined,
                    color: emeraldColor,
                  ),
                  _buildStatCard(
                    title: AppStrings.get('block_rate'),
                    value: '${blockRate.toStringAsFixed(1)}%',
                    icon: Icons.pie_chart_outline_rounded,
                    color: Colors.purpleAccent.shade100,
                  ),
                  _buildStatCard(
                    title: AppStrings.get('data_saved'),
                    value: '${dataSavedMb.toStringAsFixed(1)} MB',
                    icon: Icons.data_saver_on_rounded,
                    color: Colors.amberAccent,
                  ),
                ],
              ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1),

              const SizedBox(height: 28),

              // Traffic Overview Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          AppStrings.get('traffic_overview'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Row(
                          children: [
                            const Icon(Icons.bolt,
                                color: Colors.amberAccent, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              '14 ms (Ultra Fast)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: accent,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 140,
                      child: LineChart(
                        LineChartData(
                          gridData: const FlGridData(show: false),
                          titlesData: const FlTitlesData(show: false),
                          borderData: FlBorderData(show: false),
                          lineBarsData: [
                            LineChartBarData(
                              spots: const [
                                FlSpot(0, 30),
                                FlSpot(1, 45),
                                FlSpot(2, 28),
                                FlSpot(3, 65),
                                FlSpot(4, 50),
                                FlSpot(5, 78),
                                FlSpot(6, 62),
                              ],
                              isCurved: true,
                              color: accent,
                              barWidth: 3,
                              isStrokeCapRound: true,
                              dotData: const FlDotData(show: false),
                              belowBarData: BarAreaData(
                                show: true,
                                color: accent.withValues(alpha: 0.12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPauseChip(
      BuildContext context, VpnProvider vpn, String label, Duration duration) {
    return InkWell(
      onTap: () => vpn.pauseProtection(duration),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(
          label,
          style: const TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade400,
                ),
              ),
              Icon(icon, size: 18, color: color),
            ],
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class GestureController extends StatelessWidget {
  final VoidCallback? onTap;
  final bool isActive;
  final bool isConnecting;
  final bool isPaused;
  final Color accentColor;

  const GestureController({
    super.key,
    required this.onTap,
    required this.isActive,
    required this.isConnecting,
    this.isPaused = false,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        isPaused ? Colors.amberAccent : (isActive ? emeraldColor : accentColor);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        width: 150,
        height: 150,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              isPaused
                  ? Colors.amber.shade900.withValues(alpha: 0.6)
                  : (isActive
                      ? emeraldDarkColor.withValues(alpha: 0.8)
                      : accentColor.withValues(alpha: 0.2)),
              const Color(0xFF161B22),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: isActive ? 36 : 18,
              spreadRadius: isActive ? 6 : 2,
            ),
          ],
          border: Border.all(
            color: color.withValues(alpha: 0.8),
            width: 3,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isConnecting)
              const SizedBox(
                width: 38,
                height: 38,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Colors.white,
                ),
              )
            else
              Icon(
                isPaused
                    ? Icons.pause_circle_outline_rounded
                    : Icons.power_settings_new_rounded,
                size: 54,
                color:
                    isActive || isPaused ? Colors.white : Colors.grey.shade300,
              ),
            const SizedBox(height: 8),
            Text(
              isConnecting
                  ? AppStrings.get('connecting')
                  : (isPaused
                      ? AppStrings.get('paused')
                      : (isActive
                          ? AppStrings.get('protected')
                          : AppStrings.get('tap_to_start'))),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
