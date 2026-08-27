import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/history_provider.dart';
import '../screens/entry_detail_screen.dart';
import '../theme/app_colors.dart';

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
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                      child: Icon(Icons.assignment_turned_in, color: theme.colorScheme.primary),
                    ),
                    title: Text(entry.engineId, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(dateFormat.format(entry.timestamp)),
                    trailing: Icon(
                      entry.synced ? Icons.cloud_done : Icons.cloud_off,
                      color: entry.synced ? Colors.green : Colors.grey,
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => EntryDetailScreen(entry: entry)),
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
