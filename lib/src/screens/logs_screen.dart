import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_info.dart';
import '../providers/vpn_provider.dart';
import '../providers/theme_provider.dart';
import '../i18n/app_strings.dart';

const Color emeraldColor = Color(0xFF10B981);
const Color emeraldDarkColor = Color(0xFF065F46);

/// The query log as CSV. Fields with a comma, quote or newline are quoted.
String logsToCsv(List<DnsLogItem> logs, String Function(int uid) appName) {
  String field(String value) => value.contains(RegExp(r'[",\n]'))
      ? '"${value.replaceAll('"', '""')}"'
      : value;
  final csv = StringBuffer()..writeln('ID,Timestamp,Domain,Status,App');
  for (final item in logs) {
    csv.writeln([
      field(item.id),
      item.timestamp.toIso8601String(),
      field(item.domain),
      item.isBlocked ? 'BLOCKED' : 'ALLOWED',
      field(appName(item.uid)),
    ].join(','));
  }
  return csv.toString();
}

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  String _searchQuery = '';
  String _statusFilter = 'all'; // 'all', 'blocked', 'allowed'

  /// Copies the log to the clipboard as CSV. The app has no way to write a
  /// file the user can reach, and it used to claim an export it never made.
  void _exportLogsCsv(List<DnsLogItem> logs) {
    final csv = logsToCsv(
        logs, (uid) => context.read<VpnProvider>().appInfo(uid).displayName);
    Clipboard.setData(ClipboardData(text: csv));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppStrings.get('logs_csv_copied')
            .replaceAll('{count}', '${logs.length}')),
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
      final appFilter = vpn.logAppFilter;
      if (appFilter != null && log.uid != appFilter) return false;
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
                hintText: AppStrings.get('logs_filter_hint'),
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
                _buildFilterChip(
                    'all', AppStrings.get('logs_chip_all'), accent),
                const SizedBox(width: 8),
                _buildFilterChip('blocked', AppStrings.get('logs_blocked'),
                    Colors.redAccent),
                const SizedBox(width: 8),
                _buildFilterChip(
                    'allowed', AppStrings.get('logs_allowed'), emeraldColor),
                // Below Android 10 every query is an unknown app, so there is nothing to pick.
                if (vpn.perAppSupported) ...[
                  const Spacer(),
                  IconButton(
                    key: const Key('logs_app_filter'),
                    tooltip: AppStrings.get('logs_filter_app'),
                    icon: Icon(Icons.apps_rounded, color: accent),
                    onPressed: () => _pickApp(vpn),
                  ),
                ],
              ],
            ),
          ),
          if (vpn.logAppFilter != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InputChip(
                  key: const Key('logs_app_chip'),
                  label: Text(AppStrings.get('logs_app_chip').replaceAll(
                      '%s', vpn.appInfo(vpn.logAppFilter!).displayName)),
                  deleteIcon: const Icon(Icons.cancel, size: 18),
                  onDeleted: () => vpn.setLogAppFilter(null),
                ),
              ),
            ),
          const SizedBox(height: 6),
          Expanded(
            child: logs.isEmpty
                ? Center(
                    child: Text(
                      AppStrings.get(vpn.logAppFilter == null
                          ? 'logs_empty'
                          : 'logs_empty_app'),
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
                        onTap: () => _showDomainActions(vpn, item),
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
                          vpn.showsPerAppUi && item.uid != AppInfo.unknownUid
                              ? '$timeStr · ${vpn.appInfo(item.uid).displayName}'
                              : timeStr,
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
                            item.isBlocked
                                ? AppStrings.get('logs_blocked')
                                : AppStrings.get('logs_allowed'),
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

  /// Lists the apps present in the current log so one can be picked.
  void _pickApp(VpnProvider vpn) {
    final uids = {for (final log in vpn.logs) log.uid}.toList()
      ..sort((a, b) =>
          vpn.appInfo(a).displayName.compareTo(vpn.appInfo(b).displayName));
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF161B22),
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final uid in uids)
              ListTile(
                key: Key('logs_app_option_$uid'),
                title: Text(vpn.appInfo(uid).displayName,
                    style: const TextStyle(color: Colors.white)),
                onTap: () {
                  vpn.setLogAppFilter(uid);
                  Navigator.of(sheetContext).pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Lets a logged domain be allowed or blocked from where it was noticed,
  /// instead of retyping it on the Rules screen.
  void _showDomainActions(VpnProvider vpn, DnsLogItem item) {
    final domain = item.domain.trim().toLowerCase();
    if (domain.isEmpty) return;
    final allowed = vpn.whitelist.contains(domain);
    final blocked = vpn.blacklist.contains(domain);

    void done(String messageKey) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content:
              Text(AppStrings.get(messageKey).replaceAll('{domain}', domain)),
          backgroundColor: Colors.cyan.shade900,
        ));
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Text(
                domain,
                key: const ValueKey('log-actions-domain'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(color: Colors.white10, height: 1),
            ListTile(
              key: const ValueKey('log-action-allow'),
              leading:
                  const Icon(Icons.check_circle_outline, color: emeraldColor),
              title: Text(
                AppStrings.get(
                    allowed ? 'logs_action_unallow' : 'logs_action_allow'),
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () {
                if (allowed) {
                  vpn.removeWhitelistDomain(domain);
                  done('logs_rule_removed');
                } else {
                  vpn.allowDomain(domain);
                  done('logs_allow_added');
                }
              },
            ),
            ListTile(
              key: const ValueKey('log-action-block'),
              leading: const Icon(Icons.block, color: Colors.redAccent),
              title: Text(
                AppStrings.get(
                    blocked ? 'logs_action_unblock' : 'logs_action_block'),
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () {
                if (blocked) {
                  vpn.removeBlacklistDomain(domain);
                  done('logs_rule_removed');
                } else {
                  vpn.blockDomain(domain);
                  done('logs_block_added');
                }
              },
            ),
            ListTile(
              key: const ValueKey('log-action-copy'),
              leading: const Icon(Icons.copy, color: Colors.grey),
              title: Text(
                AppStrings.get('logs_action_copy'),
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () {
                Clipboard.setData(ClipboardData(text: domain));
                done('logs_copied');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
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
