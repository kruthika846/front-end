import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/session_provider.dart';
import '../services/auth_service.dart';
import 'lock_screen.dart';
import 'login_screen.dart';

/// The app's navigator, so signing out can close every open screen.
final appNavigatorKey = GlobalKey<NavigatorState>();

/// Sign-in and lock, drawn ABOVE every screen (MaterialApp.builder): a lock covers an entry
/// form in progress and the form is still there, untouched, after unlocking.
///
/// The app locks after 10 idle minutes and opens locked when it is started again with a
/// session still open (design, section 3). Leaving the app briefly (e.g. to take a photo
/// with the camera) doesn't lock it on its own.
class AppGate extends ConsumerStatefulWidget {
  final Widget child;
  const AppGate({super.key, required this.child});

  static const idleLimit = Duration(minutes: 10);

  @override
  ConsumerState<AppGate> createState() => _AppGateState();
}

class _AppGateState extends ConsumerState<AppGate> with WidgetsBindingObserver {
  bool _restoring = true;
  DateTime _lastActive = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restore();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _checkIdle());
  }

  Future<void> _restore() async {
    Session? session;
    try {
      session = await ref.read(authServiceProvider).restore();
    } catch (_) {
      session = null; // storage unreadable: start signed out
    }
    if (!mounted) return;
    if (session != null) {
      ref.read(currentOperatorProvider.notifier).state = session.user.displayName;
      ref.read(sessionProvider.notifier).state = session;
      ref.read(lockedProvider.notifier).state = true; // reopened: locked
    }
    setState(() => _restoring = false);
  }

  void _checkIdle() {
    if (ref.read(sessionProvider) == null || ref.read(lockedProvider)) return;
    if (DateTime.now().difference(_lastActive) >= AppGate.idleLimit) {
      ref.read(lockedProvider.notifier).state = true;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkIdle();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Signed out: close whatever was open, so the next user starts on their own home.
    ref.listen(sessionProvider, (prev, next) {
      if (prev != null && next == null) appNavigatorKey.currentState?.popUntil((r) => r.isFirst);
    });
    final session = ref.watch(sessionProvider);
    final locked = ref.watch(lockedProvider);
    final Widget? cover = _restoring
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : session == null
            ? const LoginScreen()
            : locked
                ? const LockScreen()
                : null;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _lastActive = DateTime.now(), // any touch counts as activity
      child: Stack(
        children: [
          // the app's screens stay alive underneath, but can't be used while covered
          Offstage(offstage: cover != null && session == null, child: widget.child),
          if (cover != null)
            // its own Overlay: text fields need one, and the app's is under the cover
            // (keyed: a new cover - sign-in after a lock - gets a fresh Overlay)
            Positioned.fill(
              child: Overlay(key: ValueKey(cover.runtimeType), initialEntries: [OverlayEntry(builder: (_) => cover)]),
            ),
        ],
      ),
    );
  }
}
