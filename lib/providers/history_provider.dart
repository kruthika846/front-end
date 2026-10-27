import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/logbook_entry.dart';
import 'repository_providers.dart';

/// Backs both the Records list and the Daily Log table of one generator.
/// Fetched per generator: a shared "30 newest" list filtered afterwards let
/// one busy generator push another's entries off its own screen.
/// Call `ref.invalidate(recentEntriesProvider)` after a successful save
/// to force every generator's list to re-fetch from SQLite.
final recentEntriesProvider = FutureProvider.autoDispose.family<List<LogbookEntry>, int>((ref, generatorNumber) async {
  final repo = ref.watch(logbookRepositoryProvider);
  return repo.fetchRecentEntries(limit: 30, generatorNumber: generatorNumber);
});
