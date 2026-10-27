import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/session_provider.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';
import '../theme/app_colors.dart';
import 'department_screen.dart';
import 'log_book_screen.dart';
import 'me_screen.dart';
import 'sync_screen.dart';

class _Tab {
  final String label;
  final IconData icon;
  final Widget page;
  const _Tab(this.label, this.icon, this.page);
}

/// The tabs change with the role (design, section 3):
///  Duty Engineer: Capture, Log book, Sync, Me. Chief Engineer and Captain add Sign.
///  Dashboard viewer: Log book, Dashboard, Me. Administrator: Users, Me.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  Timer? _timer;

  // Sync every 45 seconds while the app is open, and when it comes back to the front
  // (design, section 3). With the app closed nothing syncs.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 45), (_) => _sync());
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  void _sync() {
    if (ref.read(sessionProvider) != null && !ref.read(lockedProvider)) ref.read(syncProvider.notifier).syncNow();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  static List<_Tab> tabsFor(SessionUser user) => [
        if (user.canCapture) const _Tab('Capture', Icons.photo_camera_outlined, DepartmentScreen()),
        if (user.role != Roles.admin) const _Tab('Log book', Icons.menu_book_outlined, LogBookScreen()),
        if (user.canCapture) const _Tab('Sync', Icons.sync, SyncScreen()),
        if (user.canSign)
          const _Tab('Sign', Icons.draw_outlined, _ComingTab(
            title: 'Sign',
            text: 'Logs waiting for your signature, by day: sign with your 6-digit PIN, or open one and send it back '
                'with a reason. Coming in Phase 3.',
          )),
        if (user.role == Roles.viewer) const _Tab('Dashboard', Icons.insights_outlined, _DashboardTab()),
        if (user.role == Roles.admin)
          const _Tab('Users', Icons.group_outlined, _ComingTab(
            title: 'Users',
            text: 'Add users, deactivate them, reset passwords and PINs. Coming in Phase 4 — until then use the '
                'Administrator page of the LogBridge server.',
          )),
        const _Tab('Me', Icons.person_outline, MeScreen()),
      ];

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    if (session == null) return const SizedBox.shrink();
    final tabs = tabsFor(session.user);
    final index = _index.clamp(0, tabs.length - 1);

    return Scaffold(
      body: Column(
        children: [
          if (session.offline) const _OfflineBanner() else if (session.user.canCapture) const _SyncBanner(),
          Expanded(child: IndexedStack(index: index, children: [for (final t in tabs) t.page])),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        backgroundColor: AppColors.ink800,
        indicatorColor: AppColors.cyan.withValues(alpha: 0.18),
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [for (final t in tabs) NavigationDestination(icon: Icon(t.icon), label: t.label)],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.gold.withValues(alpha: 0.16),
      padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 6, 16, 6),
      child: const Text(
        'Signed in without a connection to the server. Everything you capture stays on this tablet.',
        style: TextStyle(color: AppColors.gold, fontSize: 12.5),
      ),
    );
  }
}

/// The last sync is always in view: a banner when it is more than 2 days old, an alarm after 7
/// (design, section 6). Also when the server no longer accepts the sign-in.
class _SyncBanner extends ConsumerWidget {
  const _SyncBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(syncProvider);
    final days = s.daysSinceSync;
    String? text;
    var color = AppColors.gold;
    if (s.needsSignIn) {
      text = 'Sync stopped: sign out and sign in again with a connection.';
      color = AppColors.alarm;
    } else if (days != null && days >= 7) {
      text = 'Not synced for $days days. Connect to the ship or office network now.';
      color = AppColors.alarm;
    } else if (days != null && days >= 2) {
      text = 'Last synced $days days ago. Connect to the ship or office network to send your logs.';
    } else if (s.lastOk == null && s.pendingOps > 0) {
      text = 'Not synced yet: ${s.pendingOps} change(s) waiting for a connection to the server.';
    }
    if (text == null) return SizedBox(height: MediaQuery.of(context).padding.top);
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.16),
      padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 6, 16, 6),
      child: Text(text, style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600)),
    );
  }
}

/// A tab whose screen arrives in a later phase: says what it will do.
class _ComingTab extends StatelessWidget {
  final String title;
  final String text;
  const _ComingTab({required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted, fontSize: 15)),
          ),
        ),
      ),
    );
  }
}

/// The dashboard is a separate page of the LogBridge server with its own sign-in (design, section 3).
class _DashboardTab extends ConsumerWidget {
  const _DashboardTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final server = ref.watch(sessionProvider)?.serverUrl ?? '';
    final url = '$server/dashboard/';
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Totals, trends, out-of-range values and missing logs, from signed logs only. '
                'It opens in the browser and asks you to sign in there.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 15),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open the dashboard'),
              ),
              const SizedBox(height: 8),
              Text(url, style: const TextStyle(color: AppColors.textFaint, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
