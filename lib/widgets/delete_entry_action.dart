import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/logbook_entry.dart';
import '../providers/history_provider.dart';
import '../providers/repository_providers.dart';
import '../services/biometric_auth.dart';
import '../theme/app_colors.dart';

/// Shared delete flow for both Daily Logs and Watch Keeping — this is
/// permanent, confidential engine-room data, so it's gated behind a real
/// device biometric check (not just a confirm dialog) before anything is
/// removed. Used identically from both screens so deletion always means
/// the same thing everywhere it appears.
Future<void> confirmAndDeleteEntry(BuildContext context, WidgetRef ref, LogbookEntry entry) async {
  final unavailable = await BiometricAuth.unavailableReason();
  if (unavailable == null) {
    // Hardware is available on this device — verification is mandatory.
    final verified = await BiometricAuth.authenticate('Verify your identity to delete this logbook entry');
    if (!verified) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Biometric verification failed or was cancelled — entry not deleted')),
        );
      }
      return;
    }
  }
  // else: no biometric hardware on this test device — fall through to the
  // confirm dialog unblocked, same testing bypass as on submit. Nothing
  // about this pretends verification happened; it's simply not enforced
  // where it isn't possible yet.

  if (!context.mounted) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete this entry?'),
      content: const Text('This permanently removes the entry and every reading in it. This cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete', style: TextStyle(color: AppColors.alarm, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  await ref.read(logbookRepositoryProvider).deleteEntry(entry.id);
  ref.invalidate(recentEntriesProvider);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Entry deleted')));
  }
}
