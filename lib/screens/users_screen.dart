import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/session_provider.dart';
import '../services/auth_service.dart';
import '../services/users_service.dart';
import '../theme/app_colors.dart';

const _roles = [Roles.duty, Roles.chief, Roles.captain, Roles.viewer, Roles.admin];

/// The Users tab (Administrator): add users, change their role, deactivate them, reset
/// passwords and signing PINs, unlock a locked account (design, section 3).
class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  List<AdminUser>? _users;
  String? _error;

  UsersService get _api => UsersService(ref.read(sessionProvider)!);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final users = await _api.list();
      if (!mounted) return;
      setState(() {
        _users = users;
        _error = null;
      });
    } on UsersException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      // an answer this app can't read: say so instead of spinning forever
      if (mounted) setState(() => _error = 'Could not load the users: $e');
    }
  }

  void _snack(String text, {bool bad = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: bad ? AppColors.alarm : null));

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      _snack(done);
      _load();
    } on UsersException catch (e) {
      _snack(e.message, bad: true);
    }
  }

  Future<void> _add() async {
    final username = TextEditingController();
    final name = TextEditingController();
    final password = TextEditingController();
    final pin = TextEditingController();
    var role = Roles.duty;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Add user'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: username, autocorrect: false, decoration: const InputDecoration(labelText: 'Username (e.g. j.smith)')),
                  const SizedBox(height: 10),
                  TextField(controller: name, decoration: const InputDecoration(labelText: 'Full name')),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: role,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: [for (final r in _roles) DropdownMenuItem(value: r, child: Text(Roles.label(r)))],
                    onChanged: (v) => setState(() => role = v ?? role),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                      controller: password,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'First password (at least 8 characters)')),
                  if (Roles.approvers.contains(role)) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: pin,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: const InputDecoration(labelText: 'Signing PIN (6 digits, optional)', counterText: ''),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _run(
      () => _api.add(
        username: username.text.trim(),
        displayName: name.text.trim().isEmpty ? username.text.trim() : name.text.trim(),
        role: role,
        password: password.text,
        pin: Roles.approvers.contains(role) ? pin.text.trim() : null,
      ),
      'User added. Tell them their username and first password; they change it under Me.',
    );
  }

  Future<String?> _ask(String title, String label, {bool secret = true, bool digits = false}) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: c,
            autofocus: true,
            obscureText: secret,
            keyboardType: digits ? TextInputType.number : null,
            maxLength: digits ? 6 : null,
            decoration: InputDecoration(labelText: label, counterText: ''),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save')),
        ],
      ),
    );
  }

  Future<void> _action(AdminUser u, String what) async {
    switch (what) {
      case 'password':
        final p = await _ask('New password for ${u.displayName}', 'At least 8 characters');
        if (p != null) await _run(() => _api.update(u.id, {'password': p}), 'Password reset. Their sessions on other devices end.');
      case 'pin':
        final p = await _ask('New signing PIN for ${u.displayName}', '6 digits', digits: true);
        if (p != null) await _run(() => _api.update(u.id, {'pin': p}), 'Signing PIN reset.');
      case 'unlock':
        await _run(() => _api.update(u.id, {'unlock': true}), '${u.displayName} unlocked.');
      case 'deactivate':
        final sure = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Deactivate ${u.displayName}?'),
            content: const Text('They can no longer sign in, on any tablet. You can activate them again later.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.alarm),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Deactivate'),
              ),
            ],
          ),
        );
        if (sure != true) return;
        await _run(() => _api.update(u.id, {'active': false}), '${u.displayName} deactivated. Their sign-in stops at once.');
      case 'activate':
        await _run(() => _api.update(u.id, {'active': true}), '${u.displayName} active again.');
      default:
        if (what.startsWith('role:')) {
          await _run(() => _api.update(u.id, {'role': what.substring(5)}), '${u.displayName} is now ${Roles.label(what.substring(5))}.');
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(sessionProvider)?.user;
    return Scaffold(
      appBar: AppBar(title: const Text('Users')),
      floatingActionButton:
          FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.person_add), label: const Text('Add user')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.gold)),
            if (_users == null && _error == null)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
            for (final u in _users ?? const <AdminUser>[])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    leading: CircleAvatar(
                      backgroundColor: (u.active ? AppColors.cyan : AppColors.textFaint).withValues(alpha: 0.15),
                      child: Icon(Icons.person, color: u.active ? AppColors.cyan : AppColors.textFaint),
                    ),
                    title: Text(u.displayName, style: TextStyle(fontWeight: FontWeight.w700, color: u.active ? null : AppColors.textFaint)),
                    subtitle: Text([
                      '@${u.username}',
                      Roles.label(u.role),
                      if (!u.active) 'deactivated',
                      if (u.locked) 'locked (wrong passwords)',
                      if (u.pinLocked) 'PIN locked',
                      if (Roles.approvers.contains(u.role) && !u.hasPin) 'no signing PIN',
                    ].join('  ·  ')),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) => _action(u, v),
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'password', child: Text('Reset password')),
                        if (Roles.approvers.contains(u.role)) const PopupMenuItem(value: 'pin', child: Text('Reset signing PIN')),
                        if (u.locked || u.pinLocked) const PopupMenuItem(value: 'unlock', child: Text('Unlock')),
                        // never your own role: making yourself a Duty Engineer would take the Users tab away
                        if (u.id != me?.id)
                          for (final r in _roles)
                            if (r != u.role) PopupMenuItem(value: 'role:$r', child: Text('Make ${Roles.label(r)}')),
                        if (u.id != me?.id)
                          u.active
                              ? const PopupMenuItem(value: 'deactivate', child: Text('Deactivate'))
                              : const PopupMenuItem(value: 'activate', child: Text('Activate again')),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
