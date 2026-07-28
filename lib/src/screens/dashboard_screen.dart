import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/vpn_provider.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VpnProvider>();
    final stats = vpn.stats;

    final int totalQueries = stats['total_queries'] ?? 0;
    final int blockedQueries = stats['blocked_queries'] ?? 0;
    final double blockRate = (stats['block_rate_percentage'] as num?)?.toDouble() ?? 0.0;
    final double dataSavedMb = ((stats['estimated_data_saved_bytes'] as num?)?.toDouble() ?? 0.0) / (1024 * 1024);

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
                        'AEGIS NET',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.0,
                          color: Colors.cyanAccent.shade200,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Rust-Powered Privacy Guard',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: vpn.isVpnActive
                          ? Colors.emerald.shade900.withOpacity(0.4)
                          : Colors.red.shade900.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: vpn.isVpnActive ? Colors.emeraldAccent : Colors.redAccent,
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
                            color: vpn.isVpnActive ? Colors.emeraldAccent : Colors.redAccent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          vpn.isVpnActive ? 'PROTECTED' : 'UNPROTECTED',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: vpn.isVpnActive ? Colors.emeraldAccent : Colors.redAccent,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 36),

              // Glowing Interactive Power Toggle Button
              Center(
                child: GestureController(
                  onTap: vpn.isConnecting ? null : () => vpn.toggleVpn(),
                  isActive: vpn.isVpnActive,
                  isConnecting: vpn.isConnecting,
                ),
              ),

              const SizedBox(height: 36),

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
                    title: 'Total Queries',
                    value: '$totalQueries',
                    icon: Icons.swap_vert_rounded,
                    color: Colors.cyanAccent,
                  ),
                  _buildStatCard(
                    title: 'Ads Blocked',
                    value: '$blockedQueries',
                    icon: Icons.shield_outlined,
                    color: Colors.emeraldAccent,
                  ),
                  _buildStatCard(
                    title: 'Block Rate',
                    value: '${blockRate.toStringAsFixed(1)}%',
                    icon: Icons.pie_chart_outline_rounded,
                    color: Colors.purpleAccent.shade100,
                  ),
                  _buildStatCard(
                    title: 'Data Saved',
                    value: '${dataSavedMb.toStringAsFixed(1)} MB',
                    icon: Icons.data_saver_on_rounded,
                    color: Colors.amberAccent,
                  ),
                ],
              ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1),

              const SizedBox(height: 28),

              // Activity Chart Card
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
                        const Text(
                          'Traffic Overview',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'DNS Engine: Active',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.cyanAccent.shade100,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 140,
                      child: LineChart(
                        LineChartData(
                          gridData: FlGridData(show: false),
                          titlesData: FlTitlesData(show: false),
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
                              color: Colors.cyanAccent,
                              barWidth: 3,
                              isStrokeCapRound: true,
                              dotData: FlDotData(show: false),
                              belowBarData: BarAreaData(
                                show: true,
                                color: Colors.cyanAccent.withOpacity(0.12),
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
        border: Border.all(color: Colors.white.withOpacity(0.08)),
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

  const GestureController({
    super.key,
    required this.onTap,
    required this.isActive,
    required this.isConnecting,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? Colors.emeraldAccent : Colors.cyanAccent;

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
              isActive
                  ? Colors.emerald.shade800.withOpacity(0.8)
                  : Colors.cyan.shade900.withOpacity(0.6),
              const Color(0xFF161B22),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: isActive
                  ? Colors.emeraldAccent.withOpacity(0.4)
                  : Colors.cyanAccent.withOpacity(0.2),
              blurRadius: isActive ? 36 : 18,
              spreadRadius: isActive ? 6 : 2,
            ),
          ],
          border: Border.all(
            color: isActive ? Colors.emeraldAccent : Colors.cyanAccent.withOpacity(0.6),
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
                Icons.power_settings_new_rounded,
                size: 54,
                color: isActive ? Colors.white : Colors.grey.shade300,
              ),
            const SizedBox(height: 8),
            Text(
              isConnecting
                  ? 'CONNECTING'
                  : (isActive ? 'PROTECTED' : 'TAP TO START'),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: isActive ? Colors.emeraldAccent : Colors.grey.shade300,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
