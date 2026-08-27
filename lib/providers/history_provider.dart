import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/logbook_entry.dart';
import 'repository_providers.dart';

/// Backs both the Records list and the Daily Log table on the home screen.
/// Call `ref.invalidate(recentEntriesProvider)` after a successful save
/// to force it to re-fetch from SQLite.
final recentEntriesProvider = FutureProvider.autoDispose<List<LogbookEntry>>((ref) async {
  final repo = ref.watch(logbookRepositoryProvider);
  return repo.fetchRecentEntries(limit: 30);
});
