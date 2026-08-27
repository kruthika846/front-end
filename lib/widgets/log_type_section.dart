import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// A collapsible log type ("Daily Logs" / "Records") within a generator's
/// screen. Shared between generator screens so each one looks identical.
class LogTypeSection extends StatelessWidget {
  final String storageKey;
  final String title;
  final IconData icon;
  final Color accent;
  final Widget child;

  const LogTypeSection({
    super.key,
    required this.storageKey,
    required this.title,
    required this.icon,
    required this.accent,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.ink900.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: Material(
          type: MaterialType.transparency,
          child: ExpansionTile(
            key: PageStorageKey(storageKey),
            initiallyExpanded: true,
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            iconColor: accent,
            collapsedIconColor: accent,
            title: Row(
              children: [
                Icon(icon, size: 15, color: accent),
                const SizedBox(width: 8),
                Text(title, style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 12.5)),
              ],
            ),
            children: [child],
          ),
        ),
      ),
    );
  }
}
