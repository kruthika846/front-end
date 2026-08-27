import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/param_definition.dart';
import '../providers/entry_form_provider.dart';
import '../theme/app_colors.dart';
import 'edit_value_dialog.dart';
import 'panel_comment_field.dart';

/// A schematic "look" at the generator set, built from the same silhouette
/// as the real machine's cylinder heads (rounded-top caps, a red badge on
/// top like the valve knobs in the reference photo) instead of plain
/// circles or rectangles. Turbocharger and the cylinder bank are their own
/// distinct panels — separated the way you'd actually walk up to each part
/// of the machine — and everything wraps into a grid so nothing needs to
/// scroll or gets cramped when a real 3-digit reading is typed in.
class EngineDiagram extends StatelessWidget {
  final ParamDefinition turboInlet;
  final ParamDefinition turboOutlet;
  final ParamDefinition mean;
  final List<ParamDefinition> cylinders;

  const EngineDiagram({
    super.key,
    required this.turboInlet,
    required this.turboOutlet,
    required this.mean,
    required this.cylinders,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.ink700, AppColors.ink600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.cyan.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(color: AppColors.blue.withValues(alpha: 0.28), blurRadius: 28, offset: const Offset(0, 12)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.settings_input_component, color: AppColors.cyan, size: 15),
              const SizedBox(width: 6),
              Text(
                'GENERATOR SET',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textMuted,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(child: _DiamondReading(definition: mean, label: 'MEAN EXH')),
          const SizedBox(height: 18),
          _SubPanel(
            title: 'TURBOCHARGER',
            icon: Icons.cyclone_outlined,
            accent: AppColors.gold,
            groupKey: 'remote::${turboInlet.group}',
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              runSpacing: 12,
              children: [
                _CylinderCap(definition: turboInlet, badgeLabel: 'IN', accent: AppColors.gold),
                _CylinderCap(definition: turboOutlet, badgeLabel: 'OUT', accent: AppColors.gold),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _CylinderBankExpander(cylinders: cylinders),
        ],
      ),
    );
  }
}

/// A darker inset panel that groups a related set of cylinder caps under
/// its own labeled heading — this is the "separate panel per system" split
/// (Turbocharger vs. Cylinder Bank) instead of one crowded strip.
class _SubPanel extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final Widget child;
  final String? groupKey;

  const _SubPanel({required this.title, required this.icon, required this.accent, required this.child, this.groupKey});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: AppColors.ink900.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: accent),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 0.8),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
          if (groupKey != null) ...[
            const SizedBox(height: 12),
            PanelCommentField(groupKey: groupKey!),
          ],
        ],
      ),
    );
  }
}

/// A collapsible "drop-down" panel for the cylinder bank — starts closed
/// showing just a count of how many of the 6 are filled in, tap to expand
/// and reveal all six cylinder caps. Keeps the diagram compact until the
/// operator actually needs to key in exhaust temperatures.
class _CylinderBankExpander extends ConsumerWidget {
  final List<ParamDefinition> cylinders;

  const _CylinderBankExpander({required this.cylinders});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final values = ref.watch(entryFormProvider.select((s) => s.values));
    final filledCount = cylinders.where((c) => (values[c.key] ?? '').isNotEmpty).length;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.ink900.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.cyan.withValues(alpha: 0.22)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: Material(
          type: MaterialType.transparency,
          child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
          iconColor: AppColors.cyan,
          collapsedIconColor: AppColors.cyan,
          title: Row(
            children: [
              const Icon(Icons.view_column_outlined, size: 14, color: AppColors.cyan),
              const SizedBox(width: 6),
              const Text(
                'CYLINDER BANK',
                style: TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 0.8),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: filledCount == cylinders.length
                      ? AppColors.good.withValues(alpha: 0.18)
                      : AppColors.textFaint.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$filledCount/${cylinders.length}',
                  style: TextStyle(
                    color: filledCount == cylinders.length ? AppColors.good : AppColors.textMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          children: [
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 14,
              children: [
                for (var i = 0; i < cylinders.length; i++)
                  _CylinderCap(definition: cylinders[i], badgeLabel: '${i + 1}', accent: AppColors.cyan),
              ],
            ),
            const SizedBox(height: 12),
            PanelCommentField(groupKey: 'remote::${cylinders.first.group}'),
          ],
          ),
        ),
      ),
    );
  }
}

/// One editable reading shaped like a real cylinder head: a rounded-top cap
/// with a red badge on top standing in for the valve knobs in the photo.
/// Reused for every cylinder and for the turbo IN/OUT readings so the whole
/// diagram reads as one consistent shape language, not a mix of widgets.
class _CylinderCap extends ConsumerWidget {
  final ParamDefinition definition;
  final String badgeLabel;
  final Color accent;

  const _CylinderCap({required this.definition, required this.badgeLabel, required this.accent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(entryFormProvider.select((s) => s.values[definition.key] ?? ''));
    final notifier = ref.read(entryFormProvider.notifier);
    final hasValue = value.isNotEmpty;

    return SizedBox(
      width: 96,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFD8483C),
              boxShadow: [BoxShadow(color: const Color(0xFFD8483C).withValues(alpha: 0.5), blurRadius: 8)],
            ),
            alignment: Alignment.center,
            child: Text(
              badgeLabel,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11),
            ),
          ),
          const SizedBox(height: 6),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                constraints: const BoxConstraints(minHeight: 92),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: hasValue
                        ? [accent.withValues(alpha: 0.32), accent.withValues(alpha: 0.10)]
                        : const [Color(0xFF3A5680), Color(0xFF22344F)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(26),
                    topRight: Radius.circular(26),
                    bottomLeft: Radius.circular(10),
                    bottomRight: Radius.circular(10),
                  ),
                  border: Border.all(color: accent.withValues(alpha: hasValue ? 0.75 : 0.25), width: 1.4),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        initialValue: value,
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 18),
                        decoration: const InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          errorStyle: TextStyle(fontSize: 0, height: 0),
                        ),
                        onChanged: (v) => notifier.setValue(definition.key, v),
                        validator: (v) => (v == null || v.trim().isEmpty) ? '' : null,
                      ),
                      const SizedBox(height: 3),
                      Text(definition.unit, style: const TextStyle(color: AppColors.textFaint, fontSize: 10)),
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: -6,
                right: -6,
                child: EditBadge(size: 24, onTap: () => showEditValueDialog(context, ref, definition)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DiamondReading extends ConsumerWidget {
  final ParamDefinition definition;
  final String label;

  const _DiamondReading({required this.definition, required this.label});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(entryFormProvider.select((s) => s.values[definition.key] ?? ''));
    final notifier = ref.read(entryFormProvider.notifier);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label (${definition.unit})',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.textMuted,
                letterSpacing: 0.6,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 84,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.cyan.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.cyan.withValues(alpha: 0.6), width: 1.4),
              ),
              child: TextFormField(
                initialValue: value,
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 20),
                decoration: const InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  errorStyle: TextStyle(fontSize: 0, height: 0),
                ),
                onChanged: (v) => notifier.setValue(definition.key, v),
                validator: (v) => (v == null || v.trim().isEmpty) ? '' : null,
              ),
            ),
            Positioned(
              bottom: -6,
              right: -6,
              child: EditBadge(size: 24, onTap: () => showEditValueDialog(context, ref, definition)),
            ),
          ],
        ),
      ],
    );
  }
}
