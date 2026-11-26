import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../i18n/app_strings.dart';
import '../providers/network_rule.dart';
import '../providers/vpn_provider.dart';
import 'app_lock_screen.dart';

/// Settings card: which networks protection applies on, and Wi-Fi networks
/// to leave out by name (Android).
class NetworkRuleCard extends StatefulWidget {
  const NetworkRuleCard({super.key});

  @override
  State<NetworkRuleCard> createState() => _NetworkRuleCardState();
}

class _NetworkRuleCardState extends State<NetworkRuleCard>
    with WidgetsBindingObserver {
  final TextEditingController _ssidController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final vpn = context.read<VpnProvider>();
    if (vpn.ssidExceptionsOn) vpn.refreshLocationAccess();
  }

  /// The user may come back from the system's permission page.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    final vpn = context.read<VpnProvider>();
    if (vpn.ssidExceptionsOn) vpn.refreshLocationAccess();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ssidController.dispose();
    super.dispose();
  }

  void _say(String key) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(AppStrings.get(key)),
      backgroundColor: Colors.cyan.shade900,
    ));
  }

  /// Leaving a network out weakens protection, so it takes the PIN when the
  /// app lock is on.
  Future<void> _chooseScope(VpnProvider vpn, NetworkScope scope) async {
    if (scope == vpn.networkScope) return;
    if (scope != NetworkScope.all && !await requirePin(context)) return;
    await vpn.setNetworkScope(scope);
  }

  Future<void> _addSsid(VpnProvider vpn, String name,
      {bool exact = false}) async {
    if (!await requirePin(context)) return;
    final added = await vpn.addSsidException(name, exact: exact);
    if (!mounted) return;
    if (added) {
      if (!exact) _ssidController.clear();
    } else {
      _say('ssid_invalid');
    }
  }

  Future<void> _addCurrentSsid(VpnProvider vpn) async {
    final name = await vpn.currentWifiSsid();
    if (!mounted) return;
    if (name == null) {
      _say('ssid_current_unknown');
      return;
    }
    await _addSsid(vpn, name, exact: true);
  }

  Widget _scopeChip(VpnProvider vpn, NetworkScope scope, String labelKey) {
    final selected = vpn.networkScope == scope;
    const color = Colors.cyanAccent;
    return InkWell(
      key: Key('network_scope_${scope.stored}'),
      onTap: () => _chooseScope(vpn, scope),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color:
              selected ? color.withValues(alpha: 0.2) : const Color(0xFF0D1117),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? color : Colors.white12,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          AppStrings.get(labelKey),
          style: TextStyle(
            color: selected ? color : Colors.grey,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  /// Why the list may not be in use, with what fixes it.
  Widget? _accessNote(VpnProvider vpn) {
    final access = vpn.locationAccess;
    if (access.sdkInt == 0) return null;
    String? text;
    String? action;
    Future<void> Function()? onAction;
    if (!access.granted) {
      text = 'ssid_denied';
      action = 'ssid_grant';
      onAction = vpn.requestLocationAccess;
    } else if (access.locationOn == false) {
      text = 'ssid_location_off';
    } else if (access.needsBackground) {
      text = 'ssid_background_note';
      action = 'ssid_background_action';
      onAction = vpn.requestBackgroundLocation;
    }
    if (text == null) return null;
    return Container(
      key: const Key('ssid_access_note'),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF3B2F12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppStrings.get(text),
              style: TextStyle(color: Colors.grey.shade300, fontSize: 12)),
          if (action != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: Key(action),
                onPressed: onAction,
                child: Text(AppStrings.get(action),
                    style: const TextStyle(
                        color: Colors.amberAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VpnProvider>();
    final note = vpn.ssidExceptionsOn ? _accessNote(vpn) : null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.wifi_rounded,
                  color: Colors.cyanAccent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppStrings.get('settings_network_title'),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            AppStrings.get('settings_network_desc'),
            style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _scopeChip(vpn, NetworkScope.all, 'network_scope_all'),
              _scopeChip(vpn, NetworkScope.wifiOnly, 'network_scope_wifi'),
              _scopeChip(vpn, NetworkScope.mobileOnly, 'network_scope_mobile'),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  AppStrings.get('settings_ssid_title'),
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
              ),
              Switch(
                key: const Key('ssid_exceptions_switch'),
                value: vpn.ssidExceptionsOn,
                activeThumbColor: Colors.cyanAccent,
                onChanged: (val) async {
                  if (val && !await requirePin(context)) return;
                  await vpn.setSsidExceptionsOn(val);
                },
              ),
            ],
          ),
          Text(
            AppStrings.get('settings_ssid_desc'),
            style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
          ),
          if (note != null) note,
          if (vpn.ssidExceptionsOn) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('ssid_field'),
                    controller: _ssidController,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    autocorrect: false,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (value) => _addSsid(vpn, value),
                    decoration: InputDecoration(
                      hintText: AppStrings.get('ssid_hint'),
                      hintStyle: TextStyle(color: Colors.grey.shade600),
                      filled: true,
                      fillColor: const Color(0xFF0D1117),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  key: const Key('ssid_add'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyan.shade800),
                  onPressed: () => _addSsid(vpn, _ssidController.text),
                  child: Text(AppStrings.get('common_add'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('ssid_add_current'),
                onPressed: () => _addCurrentSsid(vpn),
                icon: const Icon(Icons.add_rounded,
                    color: Colors.cyanAccent, size: 16),
                label: Text(AppStrings.get('ssid_add_current'),
                    style: const TextStyle(
                        color: Colors.cyanAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
            ),
            for (final name in vpn.ssidExceptions)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.only(left: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1117),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.wifi_off_rounded,
                        color: Colors.grey, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(name,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13)),
                    ),
                    IconButton(
                      icon:
                          const Icon(Icons.close, color: Colors.grey, size: 18),
                      onPressed: () => vpn.removeSsidException(name),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
