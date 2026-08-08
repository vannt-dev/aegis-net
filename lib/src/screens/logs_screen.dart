import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/vpn_provider.dart';
import '../providers/theme_provider.dart';
import '../i18n/app_strings.dart';

const Color emeraldColor = Color(0xFF10B981);
const Color emeraldDarkColor = Color(0xFF065F46);

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  String _searchQuery = '';
  String _statusFilter = 'all'; // 'all', 'blocked', 'allowed'

  void _exportLogsCsv(List<DnsLogItem> logs) {
    final StringBuffer csv = StringBuffer();
    csv.writeln('ID,Timestamp,Domain,Status');
    for (final item in logs) {
      csv.writeln(
          '${item.id},${item.timestamp.toIso8601String()},${item.domain},${item.isBlocked ? "BLOCKED" : "ALLOWED"}');
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('CSV Logs Exported (${logs.length} entries)'),
        backgroundColor: Colors.cyan.shade900,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VpnProvider>();
    final theme = context.watch<ThemeProvider>();
    final accent = theme.primaryAccent;

    final logs = vpn.logs.where((log) {
      final matchesSearch =
          log.domain.toLowerCase().contains(_searchQuery.toLowerCase());
      if (!matchesSearch) return false;
      if (_statusFilter == 'blocked') return log.isBlocked;
      if (_statusFilter == 'allowed') return !log.isBlocked;
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
        title: Text(
          AppStrings.get('logs_title'),
          style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.file_download_outlined, color: accent),
            tooltip: AppStrings.get('export_logs'),
            onPressed: () => _exportLogsCsv(logs),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Field
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Filter domain logs...',
                hintStyle: TextStyle(color: Colors.grey.shade600),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
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
          ),

          // Status Filter Chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                _buildFilterChip('all', 'ALL LOGS', accent),
                const SizedBox(width: 8),
                _buildFilterChip('blocked', 'BLOCKED', Colors.redAccent),
                const SizedBox(width: 8),
                _buildFilterChip('allowed', 'ALLOWED', emeraldColor),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: logs.isEmpty
                ? Center(
                    child: Text(
                      'No queries captured yet',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  )
                : ListView.separated(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: logs.length,
                    separatorBuilder: (context, index) =>
                        const Divider(color: Colors.white10, height: 1),
                    itemBuilder: (context, index) {
                      final item = logs[index];
                      final timeStr =
                          DateFormat('HH:mm:ss').format(item.timestamp);

                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        leading: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: item.isBlocked
                                ? Colors.red.shade900.withValues(alpha: 0.4)
                                : emeraldDarkColor.withValues(alpha: 0.4),
                          ),
                          child: Icon(
                            item.isBlocked
                                ? Icons.block
                                : Icons.check_circle_outline,
                            size: 18,
                            color: item.isBlocked
                                ? Colors.redAccent
                                : emeraldColor,
                          ),
                        ),
                        title: Text(
                          item.domain,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          timeStr,
                          style: TextStyle(
                              color: Colors.grey.shade500, fontSize: 11),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: item.isBlocked
                                ? Colors.red.withValues(alpha: 0.15)
                                : emeraldDarkColor.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            item.isBlocked ? 'BLOCKED' : 'ALLOWED',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: item.isBlocked
                                  ? Colors.redAccent
                                  : emeraldColor,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label, Color color) {
    final isSelected = _statusFilter == value;
    return InkWell(
      onTap: () => setState(() => _statusFilter = value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.2)
              : const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : Colors.white12,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? color : Colors.grey,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
