import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/app_strings.dart';
import '../providers/app_lock_provider.dart';

const Color _panelColor = Color(0xFF161B22);

/// Asks for the app-lock PIN before an action that weakens protection.
///
/// Returns true straight away when the lock is off (or not provided at all),
/// or when the PIN was entered within [AppLockProvider.confirmGrace]. [always]
/// skips that grace, for turning the lock itself off or changing the PIN.
Future<bool> requirePin(BuildContext context, {bool always = false}) async {
  final lock = Provider.of<AppLockProvider?>(context, listen: false);
  if (lock == null || !lock.enabled) return true;
  if (!always && lock.confirmedRecently) return true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => ChangeNotifierProvider.value(
      value: lock,
      child: const _PinCheckDialog(),
    ),
  );
  return ok ?? false;
}

/// Asks for a new PIN twice. Returns it, or null when cancelled.
Future<String?> showNewPinDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _NewPinDialog(),
  );
}

/// The message for a failed [PinCheck], or null when it passed.
String? pinCheckMessage(PinCheck result, AppLockProvider lock) {
  switch (result) {
    case PinCheck.ok:
      return null;
    case PinCheck.wrong:
      final wait = lock.lockoutRemaining;
      return wait > Duration.zero
          ? AppStrings.get('lock_wait').replaceAll('%s', '${wait.inSeconds}')
          : AppStrings.get('lock_wrong');
    case PinCheck.lockedOut:
      return AppStrings.get('lock_wait')
          .replaceAll('%s', '${lock.lockoutRemaining.inSeconds}');
  }
}

/// Covers the whole app with the lock screen while the app lock is locked,
/// and tells the lock when the app goes to the background and comes back.
///
/// Sits in [MaterialApp.builder], above the navigator, so pushed routes and
/// dialogs are covered too.
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = context.read<AppLockProvider>();
    // Not `inactive`: the system VPN consent dialog only makes the app
    // inactive, and returning from it must not ask for the PIN.
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      lock.onBackground();
    } else if (state == AppLifecycleState.resumed) {
      lock.onForeground();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lock = context.watch<AppLockProvider>();
    // Until storage is read we do not know whether the app is locked, so
    // show nothing rather than flash the dashboard.
    if (!lock.loaded) {
      return const ColoredBox(color: Color(0xFF0D1117));
    }
    final locked = lock.isLocked;
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          excluding: locked,
          child: TickerMode(enabled: !locked, child: widget.child),
        ),
        if (locked) const _LockScreen(),
      ],
    );
  }
}

class _LockScreen extends StatefulWidget {
  const _LockScreen();

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  String? _message;
  bool _busy = false;

  Future<void> _submit(String pin) async {
    final lock = context.read<AppLockProvider>();
    setState(() => _busy = true);
    final result = await lock.unlock(pin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = pinCheckMessage(result, lock);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('app_lock_screen'),
      color: const Color(0xFF0D1117),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_rounded,
                    color: Colors.cyanAccent, size: 48),
                const SizedBox(height: 16),
                Text(
                  AppStrings.get('lock_locked_title'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(AppStrings.get('lock_enter_pin'),
                    style: TextStyle(color: Colors.grey.shade400)),
                const SizedBox(height: 24),
                PinPad(busy: _busy, message: _message, onSubmit: _submit),
                const SizedBox(height: 24),
                Text(
                  AppStrings.get('lock_forgot'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PinCheckDialog extends StatefulWidget {
  const _PinCheckDialog();

  @override
  State<_PinCheckDialog> createState() => _PinCheckDialogState();
}

class _PinCheckDialogState extends State<_PinCheckDialog> {
  String? _message;
  bool _busy = false;

  Future<void> _submit(String pin) async {
    final lock = context.read<AppLockProvider>();
    setState(() => _busy = true);
    final result = await lock.check(pin);
    if (!mounted) return;
    if (result == PinCheck.ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _message = pinCheckMessage(result, lock);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('pin_check_dialog'),
      backgroundColor: _panelColor,
      title: Text(AppStrings.get('lock_enter_pin'),
          style: const TextStyle(color: Colors.white, fontSize: 16)),
      content: SingleChildScrollView(
        child: PinPad(busy: _busy, message: _message, onSubmit: _submit),
      ),
      actions: [
        TextButton(
          key: const ValueKey('pin_cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(AppStrings.get('common_cancel')),
        ),
      ],
    );
  }
}

class _NewPinDialog extends StatefulWidget {
  const _NewPinDialog();

  @override
  State<_NewPinDialog> createState() => _NewPinDialogState();
}

class _NewPinDialogState extends State<_NewPinDialog> {
  String? _first;
  String? _message;

  void _submit(String pin) {
    final first = _first;
    if (first == null) {
      setState(() {
        _first = pin;
        _message = null;
      });
    } else if (first == pin) {
      Navigator.of(context).pop(pin);
    } else {
      setState(() {
        _first = null;
        _message = AppStrings.get('lock_mismatch');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('new_pin_dialog'),
      backgroundColor: _panelColor,
      title: Text(
          AppStrings.get(_first == null ? 'lock_new_pin' : 'lock_confirm_pin'),
          style: const TextStyle(color: Colors.white, fontSize: 16)),
      content: SingleChildScrollView(
        child: PinPad(
          // A new pad for the second entry, so the first one's digits go.
          key: ValueKey(_first == null ? 'pin_step_1' : 'pin_step_2'),
          message: _message,
          onSubmit: _submit,
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('pin_cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppStrings.get('common_cancel')),
        ),
      ],
    );
  }
}

/// Digit pad for 4-6 digit PINs. Buttons rather than a text field, so it
/// works above the navigator (where there is no overlay for a text field)
/// and never hands the PIN to a keyboard app.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.onSubmit,
    this.message,
    this.busy = false,
  });

  final void Function(String pin) onSubmit;
  final String? message;
  final bool busy;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _digits = '';

  void _add(String digit) {
    if (_digits.length >= AppLockProvider.maxLength) return;
    setState(() => _digits += digit);
  }

  void _back() {
    if (_digits.isEmpty) return;
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  void _ok() {
    if (!AppLockProvider.isValidPin(_digits)) return;
    final pin = _digits;
    setState(() => _digits = '');
    widget.onSubmit(pin);
  }

  Widget _key(String label, VoidCallback? onTap, {Key? key, IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: SizedBox(
        width: 60,
        height: 52,
        child: OutlinedButton(
          key: key,
          onPressed: widget.busy ? null : onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white24),
            padding: EdgeInsets.zero,
          ),
          child: icon != null
              ? Icon(icon, size: 20)
              : Text(label, style: const TextStyle(fontSize: 20)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          key: const ValueKey('pin_dots'),
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < AppLockProvider.maxLength; i++)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 5),
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _digits.length
                      ? Colors.cyanAccent
                      : Colors.transparent,
                  border: Border.all(
                      color: i < AppLockProvider.minLength
                          ? Colors.white54
                          : Colors.white24),
                ),
              ),
          ],
        ),
        SizedBox(
          height: 36,
          child: Center(
            child: widget.busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.cyanAccent),
                  )
                : message == null
                    ? null
                    : Text(
                        message,
                        key: const ValueKey('pin_message'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 12),
                      ),
          ),
        ),
        for (final row in rows)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final d in row)
                _key(d, () => _add(d), key: ValueKey('pin_key_$d')),
            ],
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _key('', _back,
                key: const ValueKey('pin_key_back'),
                icon: Icons.backspace_outlined),
            _key('0', () => _add('0'), key: const ValueKey('pin_key_0')),
            _key('', AppLockProvider.isValidPin(_digits) ? _ok : null,
                key: const ValueKey('pin_key_ok'), icon: Icons.check_rounded),
          ],
        ),
      ],
    );
  }
}

/// The app-lock section of the settings screen.
class AppLockSettingsCard extends StatelessWidget {
  const AppLockSettingsCard({super.key});

  Future<void> _turnOn(BuildContext context, AppLockProvider lock) async {
    final messenger = ScaffoldMessenger.of(context);
    final pin = await showNewPinDialog(context);
    if (pin == null) return;
    await lock.setPin(pin);
    messenger.showSnackBar(
        SnackBar(content: Text(AppStrings.get('lock_enabled_msg'))));
  }

  Future<void> _turnOff(BuildContext context, AppLockProvider lock) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await requirePin(context, always: true)) return;
    await lock.disable();
    messenger.showSnackBar(
        SnackBar(content: Text(AppStrings.get('lock_disabled_msg'))));
  }

  Future<void> _change(BuildContext context, AppLockProvider lock) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await requirePin(context, always: true)) return;
    if (!context.mounted) return;
    final pin = await showNewPinDialog(context);
    if (pin == null) return;
    await lock.setPin(pin);
    messenger.showSnackBar(
        SnackBar(content: Text(AppStrings.get('lock_changed_msg'))));
  }

  @override
  Widget build(BuildContext context) {
    // Screens pumped on their own in tests have no lock provider.
    final lock = context.watch<AppLockProvider?>();
    if (lock == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panelColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_outline_rounded,
                  color: Colors.cyanAccent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppStrings.get('lock_title'),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
              ),
              Switch(
                key: const Key('app_lock_switch'),
                value: lock.enabled,
                activeThumbColor: Colors.cyanAccent,
                onChanged: (on) =>
                    on ? _turnOn(context, lock) : _turnOff(context, lock),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            AppStrings.get('lock_desc'),
            style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
          ),
          if (lock.enabled) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('app_lock_change'),
              icon: const Icon(Icons.password_rounded, size: 16),
              label: Text(AppStrings.get('lock_change')),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.cyanAccent,
                side: const BorderSide(color: Colors.cyanAccent),
              ),
              onPressed: () => _change(context, lock),
            ),
          ],
        ],
      ),
    );
  }
}
