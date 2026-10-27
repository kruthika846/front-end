import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/session_provider.dart';
import '../services/biometric_auth.dart';
import '../theme/app_colors.dart';

/// Whether this user unlocks with a fingerprint as well as the password (their choice, in Me).
Future<bool> fingerprintUnlockOn(String username) async =>
    (await SharedPreferences.getInstance()).getBool('fingerprint_unlock:$username') ?? false;

Future<void> setFingerprintUnlock(String username, bool on) async =>
    (await SharedPreferences.getInstance()).setBool('fingerprint_unlock:$username', on);

/// Shown after 10 idle minutes and when the app is reopened: the password (checked on the
/// tablet, no network needed) or, if the user turned it on, a fingerprint opens it again.
/// Nothing captured is lost while locked.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _password = TextEditingController();
  bool _busy = false;
  bool _fingerprint = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = ref.read(sessionProvider)?.user;
    if (user != null) {
      fingerprintUnlockOn(user.username).then((on) {
        if (!mounted) return;
        setState(() => _fingerprint = on);
        if (on) _useFingerprint();
      });
    }
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _unlock() => ref.read(lockedProvider.notifier).state = false;

  Future<void> _usePassword() async {
    final user = ref.read(sessionProvider)?.user;
    if (user == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await ref.read(authServiceProvider).checkPassword(user.username, _password.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      _unlock();
    } else {
      setState(() => _error = 'Wrong password');
    }
  }

  Future<void> _useFingerprint() async {
    if (await BiometricAuth.authenticate('Unlock LogBridge')) {
      if (mounted) _unlock();
    }
  }

  Future<void> _signOut() async {
    await ref.read(authServiceProvider).signOut();
    ref.read(sessionProvider.notifier).state = null;
    ref.read(lockedProvider.notifier).state = false;
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider)?.user;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock, color: AppColors.cyan, size: 48),
                  const SizedBox(height: 16),
                  const Text('Locked', style: TextStyle(color: AppColors.textPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(
                    '${user?.displayName ?? ''}, enter your password to continue. Nothing you captured has been lost.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    autofocus: !_fingerprint,
                    decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline)),
                    onSubmitted: (_) => _usePassword(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerLeft, child: Text(_error!, style: const TextStyle(color: AppColors.alarm))),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(onPressed: _busy ? null : _usePassword, child: const Text('Unlock')),
                  ),
                  if (_fingerprint) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _useFingerprint,
                        icon: const Icon(Icons.fingerprint),
                        label: const Text('Use fingerprint'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextButton(onPressed: _signOut, child: const Text('Sign out')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
