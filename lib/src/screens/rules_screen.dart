import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _domainInputController.dispose();
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
              ? 'Successfully synced $count active ad-blocking rules!'
              : 'Synced filter lists with active engine.'),
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
        title: const Text('Add Custom Blocklist URL',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'List Name (e.g. OISD Basic)',
                hintStyle: TextStyle(color: Colors.grey),
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
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final url = urlCtrl.text.trim();
              if (name.isNotEmpty && url.startsWith('http')) {
                final source = FilterSource(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: name,
                  url: url,
                  description: 'User custom filter list',
                );
                await RuleDownloaderService.addCustomSource(source);
                if (ctx.mounted) {
                  setState(() {});
                  Navigator.pop(ctx);
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: emeraldColor),
            child: const Text('ADD LIST'),
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
        title: const Text(
          'Filter Rules & Engine',
          style: TextStyle(
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
            tooltip: 'Sync Live Rules',
            onPressed: _isSyncing ? null : _syncLiveFilters,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.cyanAccent,
          labelColor: Colors.cyanAccent,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: 'Filter Preset Lists'),
            Tab(text: 'Custom Rules'),
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
                  const Text(
                    'Subscribe to Filter Lists',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add_link, size: 16),
                    label: const Text('ADD URL'),
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
                  title: source.name,
                  description: source.description,
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
                const Text(
                  'Add Custom Domain Rule',
                  style: TextStyle(
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
                          hintText: 'e.g. example.com',
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
                      child: const Text('ALLOW',
                          style: TextStyle(color: Colors.white, fontSize: 11)),
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
                      child: const Text('BLOCK',
                          style: TextStyle(color: Colors.white, fontSize: 11)),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  'Custom Whitelist (Always Allowed)',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: emeraldColor),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: vpn.whitelist.isEmpty
                      ? Center(
                          child: Text('No custom whitelisted domains',
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
        ],
      ),
    );
  }

  Widget _buildPresetTile({
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
          onChanged: (val) {},
        ),
      ),
    );
  }
}
