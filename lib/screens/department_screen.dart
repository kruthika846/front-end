import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/session_provider.dart';
import '../theme/app_colors.dart';
import 'coming_soon_screen.dart';
import 'engine_room_screen.dart';

/// Top-level ship departments. Only Engine Room has real content so far —
/// Cargo Control and Navigation are placeholders until those logbooks are
/// built the same way Auxiliary Engine was.
class DepartmentScreen extends ConsumerWidget {
  const DepartmentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final operator = ref.watch(currentOperatorProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('LogBridge'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              operator != null ? 'Signed in as $operator' : 'Ship Logbook',
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _DepartmentTile(
            title: 'Engine Room',
            subtitle: 'Auxiliary engines, boilers, purifiers',
            icon: Icons.settings_input_component,
            accent: AppColors.cyan,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EngineRoomScreen())),
          ),
          const SizedBox(height: 14),
          _DepartmentTile(
            title: 'Cargo Control',
            subtitle: 'Coming soon',
            icon: Icons.inventory_2_outlined,
            accent: AppColors.gold,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ComingSoonScreen(department: 'Cargo Control')),
            ),
          ),
          const SizedBox(height: 14),
          _DepartmentTile(
            title: 'Navigation',
            subtitle: 'Coming soon',
            icon: Icons.explore_outlined,
            accent: AppColors.teal,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ComingSoonScreen(department: 'Navigation')),
            ),
          ),
        ],
      ),
    );
  }
}

class _DepartmentTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  const _DepartmentTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.ink800,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(shape: BoxShape.circle, color: accent.withValues(alpha: 0.14)),
                child: Icon(icon, color: accent, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 17)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}
