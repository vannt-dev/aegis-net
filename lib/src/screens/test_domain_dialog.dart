import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../i18n/app_strings.dart';
import '../providers/block_reason.dart';
import '../providers/vpn_provider.dart';

/// Asks whether a domain would be blocked, and why, without looking it up.
/// A blocked answer offers to allow the domain on the spot.
class TestDomainDialog extends StatefulWidget {
  const TestDomainDialog({super.key, this.initialDomain = ''});

  final String initialDomain;

  static Future<void> show(BuildContext context, {String initialDomain = ''}) {
    return showDialog<void>(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<VpnProvider>(),
        child: TestDomainDialog(initialDomain: initialDomain),
      ),
    );
  }

  @override
  State<TestDomainDialog> createState() => _TestDomainDialogState();
}

class _TestDomainDialogState extends State<TestDomainDialog> {
  late final TextEditingController _input =
      TextEditingController(text: widget.initialDomain);
  DomainVerdict? _verdict;
  bool _invalid = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _run() {
    final domain = normalizeDomainInput(_input.text);
    setState(() {
      _invalid = domain == null;
      _verdict = domain == null
          ? null
          : context.read<VpnProvider>().testDomain(domain);
    });
  }

  void _allow(String domain) {
    context.read<VpnProvider>().allowDomain(domain);
    _run();
  }

  @override
  Widget build(BuildContext context) {
    final verdict = _verdict;
    final color = verdict == null
        ? Colors.white
        : (verdict.blocked ? Colors.redAccent : const Color(0xFF10B981));

    return AlertDialog(
      backgroundColor: const Color(0xFF161B22),
      title: Text(
        AppStrings.get('test_domain_title'),
        style: const TextStyle(color: Colors.white, fontSize: 17),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('test-domain-input'),
            controller: _input,
            autofocus: widget.initialDomain.isEmpty,
            keyboardType: TextInputType.url,
            autocorrect: false,
            style: const TextStyle(color: Colors.white),
            onSubmitted: (_) => _run(),
            decoration: InputDecoration(
              hintText: AppStrings.get('test_domain_hint'),
              hintStyle: TextStyle(color: Colors.grey.shade600),
              errorText:
                  _invalid ? AppStrings.get('test_domain_invalid') : null,
            ),
          ),
          if (verdict != null) ...[
            const SizedBox(height: 16),
            Text(
              AppStrings.get(verdict.blocked
                  ? 'test_domain_blocked'
                  : 'test_domain_allowed'),
              key: const ValueKey('test-domain-verdict'),
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              verdict.describe(),
              key: const ValueKey('test-domain-reason'),
              style: TextStyle(color: Colors.grey.shade300, fontSize: 13),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            AppStrings.get('test_domain_note'),
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
          ),
        ],
      ),
      actions: [
        if (verdict != null && verdict.blocked)
          TextButton(
            key: const ValueKey('test-domain-allow'),
            onPressed: () => _allow(verdict.domain),
            child: Text(AppStrings.get('logs_action_allow'),
                style: const TextStyle(color: Color(0xFF10B981))),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppStrings.get('common_close')),
        ),
        TextButton(
          key: const ValueKey('test-domain-run'),
          onPressed: _run,
          child: Text(AppStrings.get('test_domain_run')),
        ),
      ],
    );
  }
}
