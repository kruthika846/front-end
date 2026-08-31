import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'generator_screen.dart';

/// Engine Room department — one expandable section per piece of equipment
/// (right now just Auxiliary Engine; Boiler, Purifier, etc. get added the
/// same way later). Auxiliary Engine holds Generators 1-3, each with its
/// own Daily Logs / Records / New Entry — Generator 1 carries over the
/// logbook built so far, Generators 2-3 start empty. Generator 4 is
/// removed for now, per instruction.
class EngineRoomScreen extends StatelessWidget {
  const EngineRoomScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Engine Room'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('Auxiliary Engine Logbook', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70)),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: const [
          _EquipmentSection(
            storageKey: 'engine_room::aux_engine',
            title: 'Auxiliary Engine',
            icon: Icons.settings_input_component,
            accent: AppColors.cyan,
            children: [
              _GeneratorRow(generatorNumber: 1),
              _GeneratorRow(generatorNumber: 2),
              _GeneratorRow(generatorNumber: 3),
              // Generator 4 removed for now, per instruction — the screen
              // and DB support are still generic, so adding it back later
              // is just re-adding this one row.
            ],
          ),
          SizedBox(height: 14),
          _EquipmentSection(
            storageKey: 'engine_room::main_engine',
            title: 'Main Engine',
            icon: Icons.engineering,
            accent: AppColors.gold,
            children: [
              _EmptyEquipmentNotice(text: 'Main Engine logbook coming soon'),
            ],
          ),
          // More equipment (Boiler, Purifier, ...) gets its own
          // _EquipmentSection here as it's defined.
        ],
      ),
    );
  }
}

/// A top-level collapsible piece of equipment ("Auxiliary Engine", later
/// "Boiler", "Purifier", ...). Starts expanded so it's discoverable.
class _EquipmentSection extends StatelessWidget {
  final String storageKey;
  final String title;
  final IconData icon;
  final Color accent;
  final List<Widget> children;

  const _EquipmentSection({
    required this.storageKey,
    required this.title,
    required this.icon,
    required this.accent,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.ink800,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: Material(
          type: MaterialType.transparency,
          child: ExpansionTile(
            key: PageStorageKey(storageKey),
            initiallyExpanded: true,
            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            iconColor: accent,
            collapsedIconColor: accent,
            title: Row(
              children: [
                Icon(icon, color: accent, size: 20),
                const SizedBox(width: 10),
                Text(title, style: TextStyle(color: accent, fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.3)),
              ],
            ),
            children: children,
          ),
        ),
      ),
    );
  }
}

/// Placeholder content for an equipment section that doesn't have its
/// sub-structure defined yet (same idea as the department-level "coming
/// soon" screens, just inline within Engine Room).
class _EmptyEquipmentNotice extends StatelessWidget {
  final String text;
  const _EmptyEquipmentNotice({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Text(text, style: const TextStyle(color: AppColors.textMuted)),
    );
  }
}

/// A tappable row for one generator ("Generator 1".."Generator 4") under
/// Auxiliary Engine — opens that generator's own Daily Logs / Records /
/// New Entry screen.
class _GeneratorRow extends StatelessWidget {
  final int generatorNumber;
  const _GeneratorRow({required this.generatorNumber});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.ink900.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cyan.withValues(alpha: 0.18)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          leading: const Icon(Icons.electric_bolt, color: AppColors.cyan, size: 20),
          title: Text(
            'Generator $generatorNumber',
            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 14),
          ),
          trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => GeneratorScreen(generatorNumber: generatorNumber)),
          ),
        ),
      ),
    );
  }
}
