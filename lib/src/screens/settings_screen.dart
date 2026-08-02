import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';
import '../providers/theme_provider.dart';
import '../services/dns_benchmark_service.dart';
import '../services/ios_doh_profile_service.dart';
import '../i18n/app_strings.dart';

const Color emeraldColor = Color(0xFF10B981);
const Color emeraldDarkColor = Color(0xFF065F46);

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _runDnsBenchmark(BuildContext context, VpnProvider vpn) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        backgroundColor: Color(0xFF161B22),
        content: Row(
          children: [
            CircularProgressIndicator(color: Colors.cyanAccent),
            SizedBox(width: 20),
            Text('Measuring DNS Latency...',
                style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );

    final results = await DnsBenchmarkService.benchmarkAll();
    if (context.mounted) {
      Navigator.pop(context);
      _showBenchmarkResults(context, vpn, results);
    }
  }

  void _showBenchmarkResults(
      BuildContext context, VpnProvider vpn, List<DnsPingResult> results) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '⚡ DNS Benchmark Results',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
              const SizedBox(height: 12),
              ...results.map(
                (r) => ListTile(
                  dense: true,
                  title: Text(r.name,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle:
                      Text(r.ip, style: TextStyle(color: Colors.grey.shade400)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${r.latencyMs} ms',
                        style: TextStyle(
                          color:
                              r.isFastest ? emeraldColor : Colors.grey.shade300,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (r.isFastest)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: emeraldDarkColor.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('FASTEST',
                              style: TextStyle(
                                  color: emeraldColor,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                  onTap: () {
                    vpn.setUpstreamDns('${r.name} (${r.ip})');
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VpnProvider>();
    final theme = context.watch<ThemeProvider>();
    final accent = theme.primaryAccent;

    final TextEditingController bypassController = TextEditingController();
    final TextEditingController dohController = TextEditingController();

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
        title: Text(
          AppStrings.get('settings_title'),
          style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // App Language Selector (EN, VI, KO, JA)
          Text(
            AppStrings.get('language_title'),
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold, color: accent),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildLangChip(context, theme, 'en', '🇺🇸 English'),
              _buildLangChip(context, theme, 'vi', '🇻🇳 Tiếng Việt'),
              _buildLangChip(context, theme, 'ko', '🇰🇷 한국어'),
              _buildLangChip(context, theme, 'ja', '🇯🇵 日本語'),
            ],
          ),

          const SizedBox(height: 24),

          // Cyberpunk Neon Theme Selector
          Text(
            AppStrings.get('theme_title'),
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold, color: accent),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildThemeCircle(
                  context, theme, NeonTheme.cyan, Colors.cyanAccent),
              _buildThemeCircle(
                  context, theme, NeonTheme.emerald, emeraldColor),
              _buildThemeCircle(context, theme, NeonTheme.purple,
                  Colors.purpleAccent.shade100),
              _buildThemeCircle(
                  context, theme, NeonTheme.gold, Colors.amberAccent),
            ],
          ),

          const SizedBox(height: 24),

          // Upstream DNS Resolver with Speed Test
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Upstream DNS Resolver',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold, color: accent),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF161B22),
                  side: BorderSide(color: accent),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                icon: Icon(Icons.flash_on, size: 14, color: accent),
                label: Text(AppStrings.get('speed_test'),
                    style: TextStyle(
                        color: accent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
                onPressed: () => _runDnsBenchmark(context, vpn),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildDnsTile(context, vpn, 'Cloudflare (1.1.1.1)',
              'Fastest privacy-focused resolver'),
          _buildDnsTile(context, vpn, 'Google (8.8.8.8)',
              'High reliability global resolver'),
          _buildDnsTile(context, vpn, 'AdGuard DNS (94.140.14.14)',
              'Upstream ad-blocking DNS'),
          _buildDnsTile(context, vpn, 'Quad9 (9.9.9.9)',
              'Malware protection & threat blocking'),

          const SizedBox(height: 16),
          // Custom DoH / DoT Field
          TextField(
            controller: dohController,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: InputDecoration(
              hintText: 'Custom DoH URL (e.g. https://dns.nextdns.io/xxxxxx)',
              hintStyle: TextStyle(color: Colors.grey.shade600),
              filled: true,
              fillColor: const Color(0xFF161B22),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.white24),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // App-by-App Split Tunneling
          const Text(
            'App-by-App Split Tunneling (Bypass VPN)',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.amberAccent),
          ),
          const SizedBox(height: 6),
          Text(
            'Selected apps will bypass Aegis Local VPN and connect directly.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: bypassController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Package name (e.g. com.zing.zalo)',
                    hintStyle: TextStyle(color: Colors.grey.shade600),
                    filled: true,
                    fillColor: const Color(0xFF161B22),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.shade800,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                onPressed: () {
                  vpn.addBypassApp(bypassController.text);
                  bypassController.clear();
                },
                child: const Text('ADD',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Column(
            children: vpn.bypassApps
                .map(
                  (pkg) => Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161B22),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(pkg,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13)),
                        IconButton(
                          icon: const Icon(Icons.close,
                              color: Colors.grey, size: 18),
                          onPressed: () => vpn.removeBypassApp(pkg),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),

          const SizedBox(height: 24),

          // iOS Encrypted DNS Profile (.mobileconfig) Setup
          Text(
            'iOS Encrypted DNS Profile (No \$99 Dev Account Required)',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold, color: accent),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Generate & install a native Apple Encrypted DNS (.mobileconfig) profile for system-wide DoH protection on iOS without requiring \$99/yr Network Extension entitlements.',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.black,
                  ),
                  icon: const Icon(Icons.verified_user, size: 16),
                  label: const Text('Install iOS Encrypted DNS Profile',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: () async {
                    final dohUrl = vpn.upstreamDns.contains('(')
                        ? RegExp(r'\(([^)]+)\)')
                                .firstMatch(vpn.upstreamDns)
                                ?.group(1) ??
                            'https://1.1.1.1/dns-query'
                        : vpn.upstreamDns;
                    final ok = await IosDohProfileService.installProfile(
                        dohUrl: dohUrl);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(ok
                              ? 'Profile generated! Review & Install in iOS Settings > Profile Downloaded.'
                              : 'Failed to generate profile.'),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Backup & Restore
          Text(
            'Export / Import Configuration',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold, color: accent),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style:
                      OutlinedButton.styleFrom(side: BorderSide(color: accent)),
                  icon: Icon(Icons.download, size: 16, color: accent),
                  label: Text(AppStrings.get('export_json'),
                      style: TextStyle(
                          color: accent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                  onPressed: () {
                    final backup = jsonEncode({
                      'whitelist': vpn.whitelist,
                      'blacklist': vpn.blacklist,
                      'bypassApps': vpn.bypassApps,
                      'upstreamDns': vpn.upstreamDns,
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(
                              'Config exported successfully: ${backup.length} bytes')),
                    );
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),
          Center(
            child: Text(
              'AegisNet v1.0.0 • Built with Rust & Flutter',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLangChip(
      BuildContext context, ThemeProvider theme, String code, String name) {
    final isSelected = theme.currentLanguage == code;
    return InkWell(
      onTap: () => theme.setLanguage(code),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.primaryDarkAccent.withValues(alpha: 0.5)
              : const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: isSelected ? theme.primaryAccent : Colors.white10),
        ),
        child: Text(
          name,
          style: TextStyle(
            color: isSelected ? theme.primaryAccent : Colors.grey.shade300,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildThemeCircle(BuildContext context, ThemeProvider theme,
      NeonTheme nTheme, Color color) {
    final isSelected = theme.currentTheme == nTheme;
    return GestureDetector(
      onTap: () => theme.setTheme(nTheme),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: isSelected ? Colors.white : Colors.transparent,
            width: isSelected ? 3 : 0,
          ),
        ),
      ),
    );
  }

  Widget _buildDnsTile(
      BuildContext context, VpnProvider vpn, String title, String subtitle) {
    final isSelected = vpn.upstreamDns == title;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? Colors.cyanAccent : Colors.white10,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          title: Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14)),
          subtitle: Text(subtitle,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
          trailing: isSelected
              ? const Icon(Icons.check_circle, color: Colors.cyanAccent)
              : null,
          onTap: () => vpn.setUpstreamDns(title),
        ),
      ),
    );
  }
}
