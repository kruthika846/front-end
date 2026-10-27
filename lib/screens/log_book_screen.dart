import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/session_provider.dart';
import '../services/auth_service.dart';
import '../services/log_book_service.dart';
import '../services/sync_service.dart';
import '../theme/app_colors.dart';
import '../widgets/daily_log_table.dart';

/// The log book from the server, last 7 days; this tablet's own entries when it can't be reached.
final logBookProvider = FutureProvider.autoDispose<LogBook>((ref) async {
  final session = ref.watch(sessionProvider);
  ref.watch(syncProvider.select((s) => s.lastOk)); // fetched again after each sync
  if (session == null) return const LogBook({}, fromServer: false);
  try {
    return await LogBookService(session).load();
  } catch (e) {
    return LogBook(const {}, fromServer: false, error: '$e');
  }
});

/// The Log book tab (design, section 3): each generator's daily log sheet, a column per Time
/// and Noon reading, built from the logs on the LogBridge server, so it holds every tablet's
/// logs. Signed columns are marked ✓. Dashboard viewers see signed values only.
class LogBookScreen extends ConsumerWidget {
  const LogBookScreen({super.key});

  static const generators = [1, 2, 3];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(logBookProvider);
    final viewer = ref.watch(sessionProvider)?.user.role == Roles.viewer;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Log book'),
        actions: [IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: () => ref.invalidate(logBookProvider))],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(logBookProvider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            ...book.when(
              loading: () => [const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))],
              error: (e, _) => [Text('$e', style: const TextStyle(color: AppColors.alarm))],
              data: (b) => [
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text(
                    b.fromServer
                        ? (viewer ? 'Last 7 days from the LogBridge server - signed logs only.' : 'Last 7 days from the LogBridge server. ✓ = signed.')
                        : 'The server can\'t be reached: showing the entries on this tablet.',
                    style: TextStyle(color: b.fromServer ? AppColors.textMuted : AppColors.gold, fontSize: 12.5),
                  ),
                ),
                for (final g in generators) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, left: 4),
                    child: Text('GENERATOR $g',
                        style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w800, letterSpacing: 0.8, fontSize: 13)),
                  ),
                  // from the server: its logs (none yet -> an empty sheet); offline: this tablet's entries
                  if (b.fromServer)
                    DailyLogTable(generatorNumber: g, entries: b.byGenerator[g] ?? const [], readOnly: true)
                  else if (!viewer)
                    DailyLogTable(generatorNumber: g),
                  const SizedBox(height: 22),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
