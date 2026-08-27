import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/session_provider.dart';
import '../theme/app_colors.dart';
import 'department_screen.dart';

/// Local operator sign-in. There's no crew-management backend yet, so this
/// checks against a small placeholder credential list rather than faking an
/// always-pass gate — swap _demoOperators for a real synced crew list once
/// that exists. This is a genuine (if simple) check: wrong PIN is rejected.
const _demoOperators = {
  'Chief Engineer': '1111',
  '2nd Engineer': '2222',
  '3rd Engineer': '3333',
};

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  String? _operator;
  final _pinController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  void _signIn() {
    if (_operator == null) {
      setState(() => _error = 'Select your name');
      return;
    }
    if (_demoOperators[_operator] != _pinController.text) {
      setState(() => _error = 'Incorrect PIN');
      return;
    }
    ref.read(currentOperatorProvider.notifier).state = _operator;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DepartmentScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
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
                DropdownButtonFormField<String>(
                  initialValue: _operator,
                  decoration: const InputDecoration(labelText: 'Operator', prefixIcon: Icon(Icons.badge_outlined)),
                  items: _demoOperators.keys.map((name) => DropdownMenuItem(value: name, child: Text(name))).toList(),
                  onChanged: (v) => setState(() {
                    _operator = v;
                    _error = null;
                  }),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration: const InputDecoration(labelText: 'PIN', prefixIcon: Icon(Icons.lock_outline), counterText: ''),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  onSubmitted: (_) => _signIn(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_error!, style: const TextStyle(color: AppColors.alarm, fontSize: 12.5)),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(onPressed: _signIn, child: const Text('Sign In')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
