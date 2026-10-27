import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/session_provider.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';

/// Sign-in with the user's own LogBridge account (design, section 3). The first sign-in on a
/// tablet needs the server; after that the same user can sign in with no network.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _server = TextEditingController();
  bool _showServer = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    AuthService.savedServerUrl().then((url) {
      if (!mounted) return;
      setState(() {
        _server.text = url ?? '';
        _showServer = url == null || url.isEmpty;
      });
    });
  }

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    _server.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_user.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your username and password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.saveServerUrl(_server.text);
      final session = await ref.read(authServiceProvider).signIn(_server.text, _user.text, _password.text);
      ref.read(currentOperatorProvider.notifier).state = session.user.displayName;
      ref.read(lockedProvider.notifier).state = false;
      ref.read(sessionProvider.notifier).state = session;
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(colors: [AppColors.blue, AppColors.cyan]),
                        boxShadow: [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.35), blurRadius: 24)],
                      ),
                      child: const Icon(Icons.anchor, color: Colors.white, size: 40),
                    ),
                    const SizedBox(height: 20),
                    const Text('LogBridge', style: TextStyle(color: AppColors.textPrimary, fontSize: 28, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    const Text('Sign in to continue', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
                    const SizedBox(height: 36),
                    TextField(
                      controller: _user,
                      autocorrect: false,
                      textCapitalization: TextCapitalization.none,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.badge_outlined)),
                      onChanged: (_) => setState(() => _error = null),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline)),
                      onChanged: (_) => setState(() => _error = null),
                      onSubmitted: (_) => _signIn(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(_error!, style: const TextStyle(color: AppColors.alarm, fontSize: 13)),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _busy ? null : _signIn,
                        child: _busy
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Sign In'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextButton.icon(
                      onPressed: () => setState(() => _showServer = !_showServer),
                      icon: Icon(_showServer ? Icons.expand_less : Icons.dns_outlined, size: 18),
                      label: const Text('Server address'),
                    ),
                    if (_showServer) ...[
                      TextField(
                        controller: _server,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'LogBridge server',
                          hintText: 'http://192.168.1.111:8080',
                          prefixIcon: Icon(Icons.dns_outlined),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'The ship or office LogBridge server, with its port.',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 14),
                    const Text(
                      'Signing in needs a connection the first time on this tablet. After that it also works with no connection.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textFaint, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
