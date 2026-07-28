import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VpnProvider>();
    final TextEditingController bypassController = TextEditingController();

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
        title: const Text(
          'Settings & Split Tunneling',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Upstream DNS Resolver',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
          ),
          const SizedBox(height: 8),
          _buildDnsTile(context, vpn, 'Cloudflare (1.1.1.1)', 'Fastest privacy-focused resolver'),
          _buildDnsTile(context, vpn, 'Google (8.8.8.8)', 'High reliability global resolver'),
          _buildDnsTile(context, vpn, 'AdGuard DNS (94.140.14.14)', 'Upstream ad-blocking DNS'),
          _buildDnsTile(context, vpn, 'Quad9 (9.9.9.9)', 'Malware protection & threat blocking'),

          const SizedBox(height: 24),
          const Text(
            'App-by-App Split Tunneling (Bypass VPN)',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.amberAccent),
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
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                onPressed: () {
                  vpn.addBypassApp(bypassController.text);
                  bypassController.clear();
                },
                child: const Text('ADD', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Column(
            children: vpn.bypassApps
                .map(
                  (pkg) => Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161B22),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(pkg, style: const TextStyle(color: Colors.white, fontSize: 13)),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.grey, size: 18),
                          onPressed: () => vpn.removeBypassApp(pkg),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),

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
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          subtitle: Text(subtitle, style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
          trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.cyanAccent) : null,
          onTap: () => vpn.setUpstreamDns(title),
        ),
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
