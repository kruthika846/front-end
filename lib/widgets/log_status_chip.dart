import 'package:flutter/material.dart';
import '../models/logbook_entry.dart';
import '../theme/app_colors.dart';

/// Where an entry stands as a server log (design, section 6): its four states, plus the
/// tablet-only ones - not sent yet, or saved before sync existed.
class LogStatusChip extends StatelessWidget {
  final LogbookEntry entry;
  const LogStatusChip({super.key, required this.entry});

  static (String, Color, IconData) describe(LogbookEntry e) => switch (e.status) {
        'approved' => ('Signed', AppColors.good, Icons.verified),
        'submitted' when !e.synced => ('Waiting to sync', AppColors.gold, Icons.cloud_upload_outlined),
        'submitted' => ('Waiting for signature', AppColors.cyan, Icons.hourglass_top),
        'rejected' => ('Sent back', AppColors.alarm, Icons.reply),
        'draft' => ('Not accepted', AppColors.alarm, Icons.error_outline),
        _ => ('On this tablet only', AppColors.textMuted, Icons.tablet_android),
      };

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = describe(entry);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
