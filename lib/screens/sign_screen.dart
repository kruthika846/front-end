import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/session_provider.dart';
import '../services/signing_service.dart';
import '../services/sync_service.dart';
import '../theme/app_colors.dart';
import '../widgets/pin_dialog.dart';
import 'log_review_screen.dart';

/// The Sign tab (design, section 3): logs waiting for this signer's own log type, by day;
/// sign all with the PIN, or open one and send it back with a reason.
class SignScreen extends ConsumerStatefulWidget {
  const SignScreen({super.key});

  @override
  ConsumerState<SignScreen> createState() => _SignScreenState();
}

class _SignScreenState extends ConsumerState<SignScreen> {
  List<WaitingLog>? _logs;
  Map<String, dynamic>? _config;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _config = await ref.read(authServiceProvider).cachedConfig(session.user.username);
      final logs = await SigningService(session).waiting(_config);
      if (mounted) setState(() => _logs = logs);
    } on SigningException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signAll(List<WaitingLog> day) async {
    final pin = await askSigningPin(context,
        title: 'Sign ${day.length} log(s)', message: 'Every log of ${_dayText(day.first.date)} listed here is signed with your PIN.');
    if (pin == null) return;
    final signing = SigningService(ref.read(sessionProvider)!);
    var ok = 0;
    final refused = <String>[];
    for (final l in day) {
      try {
        await signing.approve(l.id, pin);
        ok++;
      } on SigningException catch (e) {
        refused.add('${l.screenName}: ${e.message}');
        // a wrong or locked PIN is wrong for every log: stop instead of using up tries
        if (e.message.contains('PIN')) break;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      content: Text([if (ok > 0) 'Signed $ok log(s).', ...refused].join('\n')),
      backgroundColor: refused.isEmpty ? null : AppColors.alarm,
    ));
    ref.read(syncProvider.notifier).syncNow();
    _load();
  }

  static String _dayText(String date) {
    final d = DateTime.tryParse(date);
    return d == null ? date : DateFormat('EEE dd MMM yyyy').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final byDay = <String, List<WaitingLog>>{};
    for (final l in _logs ?? const <WaitingLog>[]) {
      byDay.putIfAbsent(l.date, () => []).add(l);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign'),
        actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh')],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_loading && _logs == null) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
            if (_error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(_error!, style: const TextStyle(color: AppColors.gold)),
                ),
              ),
            if (_logs != null && _logs!.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                  child: Text('Nothing is waiting for your signature.', style: TextStyle(color: AppColors.textMuted, fontSize: 15)),
                ),
              ),
            for (final day in days) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(_dayText(day).toUpperCase(),
                        style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                  ),
                  FilledButton.icon(
                    onPressed: () => _signAll(byDay[day]!),
                    icon: const Icon(Icons.draw, size: 18),
                    label: Text('Sign all (${byDay[day]!.length})'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (final l in byDay[day]!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      leading: const Icon(Icons.assignment_outlined, color: AppColors.cyan),
                      title: Text('${l.screenName}  ·  ${roundLabel(_config, l.logType, l.round)}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        'Submitted by ${l.submittedBy ?? '?'}'
                        '${l.submittedAt != null ? ' at ${DateFormat('HH:mm').format(DateTime.parse(l.submittedAt!).toLocal())}' : ''}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => LogReviewScreen(log: l, config: _config)));
                        _load();
                      },
                    ),
                  ),
                ),
              const SizedBox(height: 14),
            ],
          ],
        ),
      ),
    );
  }
}
