import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VpnProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
        title: const Text(
          'Settings & Upstream DNS',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Upstream DNS Provider',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
          ),
          const SizedBox(height: 8),
          _buildDnsTile(context, vpn, 'Cloudflare (1.1.1.1)', 'Fastest privacy-focused resolver'),
          _buildDnsTile(context, vpn, 'Google (8.8.8.8)', 'High reliability global resolver'),
          _buildDnsTile(context, vpn, 'AdGuard DNS (94.140.14.14)', 'Upstream ad-blocking DNS'),
          _buildDnsTile(context, vpn, 'Quad9 (9.9.9.9)', 'Malware protection & threat blocking'),

          const SizedBox(height: 24),
          const Text(
            'Core Engine Information',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
          ),
          const SizedBox(height: 8),
          _buildInfoTile('Rust Engine Version', 'v0.1.0-alpha'),
          _buildInfoTile('Architecture', 'Flutter + FFI + Rust Core'),
          _buildInfoTile('Active Filter Rules', '${vpn.activeRulesCount} active rules'),
          _buildInfoTile('Local Tunnel Mode', 'Split-Tunnel DNS VpnService'),

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

  Widget _buildDnsTile(BuildContext context, VpnProvider vpn, String title, String subtitle) {
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
      child: ListTile(
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(subtitle, style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
        trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.cyanAccent) : null,
        onTap: () => vpn.setUpstreamDns(title),
      ),
    );
  }

  Widget _buildInfoTile(String title, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }
}
