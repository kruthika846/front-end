import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/history_provider.dart';
import '../screens/entry_detail_screen.dart';
import '../theme/app_colors.dart';
import 'delete_entry_action.dart';

/// The flat entry list for one generator's "Records" section — only shows
/// entries logged against that generator (legacy entries with no generator
/// number recorded are treated as Generator 1).
class RecordsList extends ConsumerWidget {
  final int generatorNumber;
  const RecordsList({super.key, required this.generatorNumber});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(recentEntriesProvider);
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');
    final theme = Theme.of(context);

    return entriesAsync.when(
      loading: () => const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
      error: (e, st) => Padding(padding: const EdgeInsets.all(20), child: Text('Error: $e')),
      data: (allEntries) {
        final entries = allEntries.where((e) => (e.generatorNumber ?? 1) == generatorNumber).toList();
        if (entries.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Text('No entries yet. Tap "New Entry" below to log a reading.', style: TextStyle(color: AppColors.textMuted)),
          );
        }
        return Column(
          children: [
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => EntryDetailScreen(entry: entry)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                            child: Icon(Icons.assignment_turned_in, color: theme.colorScheme.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Full comment, no truncation — shown first
                                // so it's the first thing noticed, since a
                                // comment usually exists to explain
                                // something worth flagging.
                                if (entry.combinedComments.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Icon(Icons.comment, size: 14, color: AppColors.alarm),
                                        const SizedBox(width: 5),
                                        Expanded(
                                          child: Text(
                                            entry.combinedComments,
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                              color: AppColors.alarm,
                                              fontStyle: FontStyle.italic,
                                              fontWeight: FontWeight.w600,
                                              height: 1.35,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                Text(entry.engineId, style: const TextStyle(fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(dateFormat.format(entry.timestamp), style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            entry.synced ? Icons.cloud_done : Icons.cloud_off,
                            color: entry.synced ? Colors.green : Colors.grey,
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: AppColors.alarm, size: 20),
                            tooltip: 'Delete (biometric required)',
                            onPressed: () => confirmAndDeleteEntry(context, ref, entry),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
