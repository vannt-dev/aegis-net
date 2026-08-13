import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../i18n/app_strings.dart';
import '../providers/vpn_provider.dart';
import '../services/rule_downloader_service.dart';

const Color emeraldColor = Color(0xFF10B981);
const Color emeraldDarkColor = Color(0xFF065F46);

class RulesScreen extends StatefulWidget {
  const RulesScreen({super.key});

  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _domainInputController = TextEditingController();
  final TextEditingController _customHostDomainController =
      TextEditingController();
  final TextEditingController _customHostIpController = TextEditingController();
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Sources and their on/off state live in storage, not in the widget, so
    // the list starts out showing only the built-in presets until this lands.
    RuleDownloaderService.loadSources().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _domainInputController.dispose();
    _customHostDomainController.dispose();
    _customHostIpController.dispose();
    super.dispose();
  }

  Future<void> _syncLiveFilters() async {
    setState(() => _isSyncing = true);
    final count = await RuleDownloaderService.syncAllFilters();
    setState(() => _isSyncing = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(count > 0
              ? AppStrings.get('rules_synced_count').replaceAll('%s', '$count')
              : AppStrings.get('rules_synced')),
          backgroundColor: emeraldDarkColor,
        ),
      );
    }
  }

  void _showAddCustomSourceDialog() {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: Text(AppStrings.get('rules_add_url_title'),
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: AppStrings.get('rules_list_name_hint'),
                hintStyle: const TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: urlCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'https://raw.githubusercontent.com/...',
                hintStyle: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppStrings.get('common_cancel'),
                style: const TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final url = urlCtrl.text.trim();
              if (name.isEmpty || !url.startsWith('http')) {
                _showMessage(AppStrings.get('rules_enter_name_url'));
                return;
              }

              final source = FilterSource(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                name: name,
                url: url,
                description: AppStrings.get('rules_custom_desc'),
              );
              final added = await RuleDownloaderService.addCustomSource(source);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              setState(() {});
              if (!added) {
                _showMessage(AppStrings.get('rules_already_subscribed'));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: emeraldColor),
            child: Text(AppStrings.get('rules_add_list')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VpnProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
        title: Text(
          AppStrings.get('rules_title'),
          style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.cyanAccent),
                  )
                : const Icon(Icons.sync_rounded, color: Colors.cyanAccent),
            tooltip: AppStrings.get('rules_sync_tooltip'),
            onPressed: _isSyncing ? null : _syncLiveFilters,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.cyanAccent,
          labelColor: Colors.cyanAccent,
          unselectedLabelColor: Colors.grey,
          tabs: [
            Tab(text: AppStrings.get('rules_tab_presets')),
            Tab(text: AppStrings.get('rules_tab_custom')),
            Tab(text: AppStrings.get('rules_tab_hosts')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Filter Sources Presets
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    AppStrings.get('rules_subscribe'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add_link, size: 16),
                    label: Text(AppStrings.get('rules_add_url')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.cyanAccent,
                      side: const BorderSide(color: Colors.cyanAccent),
                    ),
                    onPressed: _showAddCustomSourceDialog,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...RuleDownloaderService.allSources.map(
                (source) => _buildPresetTile(
                  id: source.id,
                  title: source.localizedName,
                  description: source.localizedDescription,
                  enabled: source.isEnabled,
                ),
              ),
            ],
          ),

          // Custom Whitelist / Blacklist Tab
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.get('rules_add_domain'),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _domainInputController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: AppStrings.get('rules_domain_hint'),
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
                        backgroundColor: emeraldDarkColor,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                      ),
                      onPressed: () {
                        vpn.addWhitelistDomain(_domainInputController.text);
                        _domainInputController.clear();
                      },
                      child: Text(AppStrings.get('rules_allow'),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11)),
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                      ),
                      onPressed: () {
                        vpn.addBlacklistDomain(_domainInputController.text);
                        _domainInputController.clear();
                      },
                      child: Text(AppStrings.get('rules_block'),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11)),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  AppStrings.get('rules_whitelist_title'),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: emeraldColor),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: vpn.whitelist.isEmpty
                      ? Center(
                          child: Text(AppStrings.get('rules_no_whitelist'),
                              style: TextStyle(color: Colors.grey.shade500)))
                      : ListView.builder(
                          itemCount: vpn.whitelist.length,
                          itemBuilder: (context, index) {
                            final domain = vpn.whitelist[index];
                            return Material(
                              color: Colors.transparent,
                              child: ListTile(
                                title: Text(domain,
                                    style:
                                        const TextStyle(color: Colors.white)),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.grey),
                                  onPressed: () =>
                                      vpn.removeWhitelistDomain(domain),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),

          // Local DNS Hosts Override Tab
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Local DNS Host Mapping (Domain -> IP)',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text(
                  AppStrings.get('rules_hosts_desc'),
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _customHostDomainController,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
                        decoration: InputDecoration(
                          hintText: AppStrings.get('rules_host_domain_hint'),
                          hintStyle: TextStyle(color: Colors.grey.shade600),
                          filled: true,
                          fillColor: const Color(0xFF161B22),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Colors.white24),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _customHostIpController,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
                        decoration: InputDecoration(
                          hintText: AppStrings.get('rules_host_ip_hint'),
                          hintStyle: TextStyle(color: Colors.grey.shade600),
                          filled: true,
                          fillColor: const Color(0xFF161B22),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Colors.white24),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyan.shade700,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                      onPressed: () {
                        final domain = _customHostDomainController.text.trim();
                        final ip = _customHostIpController.text.trim();

                        if (domain.isEmpty) {
                          _showMessage(
                              AppStrings.get('rules_enter_domain_map'));
                          return;
                        }
                        // The engine ignores a mapping it cannot parse as an
                        // IP and quietly resolves the domain normally, so a
                        // typo here would otherwise look like it took effect.
                        if (!vpn.addCustomHost(domain, ip)) {
                          _showMessage('"$ip" is not a valid IP address');
                          return;
                        }

                        _customHostDomainController.clear();
                        _customHostIpController.clear();
                      },
                      child: Text(AppStrings.get('rules_map'),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11)),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  AppStrings.get('rules_active_mappings'),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.cyanAccent),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: vpn.customHosts.isEmpty
                      ? Center(
                          child: Text(AppStrings.get('rules_no_mappings'),
                              style: TextStyle(color: Colors.grey.shade500)))
                      : ListView.builder(
                          itemCount: vpn.customHosts.length,
                          itemBuilder: (context, index) {
                            final entry =
                                vpn.customHosts.entries.elementAt(index);
                            return Material(
                              color: Colors.transparent,
                              child: ListTile(
                                title: Text(entry.key,
                                    style:
                                        const TextStyle(color: Colors.white)),
                                subtitle: Text('-> ${entry.value}',
                                    style: const TextStyle(
                                        color: Colors.cyanAccent,
                                        fontSize: 12)),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.grey),
                                  onPressed: () =>
                                      vpn.removeCustomHost(entry.key),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _buildPresetTile({
    required String id,
    required String title,
    required String description,
    required bool enabled,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Material(
        color: Colors.transparent,
        child: SwitchListTile(
          title: Text(title,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          subtitle: Text(description,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
          value: enabled,
          activeTrackColor: Colors.cyanAccent.withValues(alpha: 0.5),
          activeThumbColor: Colors.cyanAccent,
          onChanged: (val) async {
            await RuleDownloaderService.setSourceEnabled(id, val);
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }
}
