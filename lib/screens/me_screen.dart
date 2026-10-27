import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../providers/session_provider.dart';
import '../services/auth_service.dart';
import '../services/biometric_auth.dart';
import '../theme/app_colors.dart';
import 'lock_screen.dart';

/// Me (design, section 3): who is signed in, change password, set the signing PIN, and this
/// device - fingerprint unlock, server, app version, lock, sign out.
class MeScreen extends ConsumerStatefulWidget {
  const MeScreen({super.key});

  @override
  ConsumerState<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends ConsumerState<MeScreen> {
  bool _fingerprint = false;
  String _version = '';

  @override
  void initState() {
    super.initState();
    final user = ref.read(sessionProvider)?.user;
    if (user != null) fingerprintUnlockOn(user.username).then((v) => mounted ? setState(() => _fingerprint = v) : null);
    PackageInfo.fromPlatform().then((p) => mounted ? setState(() => _version = '${p.version} (build ${p.buildNumber})') : null);
  }

  void _snack(String text, {bool bad = false}) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text), backgroundColor: bad ? AppColors.alarm : null));

  Future<void> _toggleFingerprint(bool on) async {
    final user = ref.read(sessionProvider)!.user;
    if (on) {
      final why = await BiometricAuth.unavailableReason();
      if (why != null) return _snack(why, bad: true);
      if (!await BiometricAuth.authenticate('Confirm your fingerprint to use it to unlock LogBridge')) return;
    }
    await setFingerprintUnlock(user.username, on);
    if (mounted) setState(() => _fingerprint = on);
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final ok = await _form('Change password', [
      TextField(controller: current, obscureText: true, decoration: const InputDecoration(labelText: 'Current password')),
      const SizedBox(height: 12),
      TextField(controller: next, obscureText: true, decoration: const InputDecoration(labelText: 'New password (at least 8 characters)')),
    ]);
    if (ok != true) return;
    if (next.text.length < 8) return _snack('The new password needs at least 8 characters', bad: true);
    try {
      final s = await ref.read(authServiceProvider).changePassword(ref.read(sessionProvider)!, current.text, next.text);
      ref.read(sessionProvider.notifier).state = s;
      _snack('Password changed');
    } on AuthException catch (e) {
      _snack(e.message, bad: true);
    }
  }

  Future<void> _setPin() async {
    final password = TextEditingController();
    final pin = TextEditingController();
    final ok = await _form('Signing PIN', [
      const Text(
        'The PIN is only for signing logs. It is separate from your password and personal to you. Never share it.',
        style: TextStyle(color: AppColors.textMuted, fontSize: 13),
      ),
      const SizedBox(height: 12),
      TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Your password')),
      const SizedBox(height: 12),
      TextField(
        controller: pin,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 6,
        decoration: const InputDecoration(labelText: 'New 6-digit PIN', counterText: ''),
      ),
    ]);
    if (ok != true) return;
    if (!RegExp(r'^\d{6}$').hasMatch(pin.text)) return _snack('The PIN must be exactly 6 digits', bad: true);
    try {
      final s = await ref.read(authServiceProvider).setPin(ref.read(sessionProvider)!, password.text, pin.text);
      ref.read(sessionProvider.notifier).state = s;
      _snack('Signing PIN saved');
    } on AuthException catch (e) {
      _snack(e.message, bad: true);
    }
  }

  Future<bool?> _form(String title, List<Widget> fields) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: fields)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      );

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('Your entries stay on this tablet. You can sign in again here, also without a connection.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(authServiceProvider).signOut();
    ref.read(sessionProvider.notifier).state = null;
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider);
    if (s == null) return const SizedBox.shrink();
    final u = s.user;
    return Scaffold(
      appBar: AppBar(title: const Text('Me')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: AppColors.cyan.withValues(alpha: 0.15),
                    child: Text(u.displayName.isEmpty ? '?' : u.displayName[0].toUpperCase(),
                        style: const TextStyle(color: AppColors.cyan, fontSize: 22, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(u.displayName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text('${u.roleLabel}  ·  @${u.username}', style: const TextStyle(color: AppColors.textMuted)),
                        const SizedBox(height: 2),
                        Text(s.offline ? 'Signed in on this tablet (no connection)' : 'Signed in with the server',
                            style: TextStyle(color: s.offline ? AppColors.gold : AppColors.good, fontSize: 12.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.password),
                  title: const Text('Change password'),
                  subtitle: const Text('Needs a connection'),
                  onTap: _changePassword,
                ),
                if (u.canSign)
                  ListTile(
                    leading: const Icon(Icons.pin_outlined),
                    title: const Text('Signing PIN'),
                    subtitle: Text(u.hasPin ? 'You have a PIN. Setting a new one replaces it.' : 'You need a PIN to sign logs'),
                    onTap: _setPin,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.fingerprint),
                  title: const Text('Unlock with fingerprint'),
                  subtitle: const Text('As well as your password, when the app is locked'),
                  value: _fingerprint,
                  onChanged: _toggleFingerprint,
                ),
                const ListTile(
                  leading: Icon(Icons.lock_clock_outlined),
                  title: Text('Locks after 10 idle minutes'),
                  subtitle: Text('and when the app is opened again'),
                ),
                ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: const Text('Server'),
                  subtitle: Text(s.serverUrl),
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('App version'),
                  subtitle: Text(_version),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => ref.read(lockedProvider.notifier).state = true,
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Lock now'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.alarm.withValues(alpha: 0.85)),
                  onPressed: _signOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign out'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
