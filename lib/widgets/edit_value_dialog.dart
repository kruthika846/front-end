import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/param_definition.dart';
import '../providers/entry_form_provider.dart';
import '../theme/app_colors.dart';

/// Opens a full-size dialog for entering one reading — the fix for gauge
/// tiles being too small to type into comfortably. Saves straight back to
/// the same form state a direct tap on the tile would, so both ways of
/// entering a value stay in sync.
Future<void> showEditValueDialog(BuildContext context, WidgetRef ref, ParamDefinition definition) async {
  final currentValue = ref.read(entryFormProvider).values[definition.key] ?? '';
  final controller = TextEditingController(text: currentValue);

  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(definition.label),
      content: TextField(
        controller: controller,
        autofocus: true,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        keyboardType: definition.inputType == ParamInputType.number
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : TextInputType.text,
        decoration: InputDecoration(suffixText: definition.unit.isEmpty ? null : definition.unit),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Save')),
      ],
    ),
  );

  if (result != null) {
    ref.read(entryFormProvider.notifier).setValue(definition.key, result);
  }
}

/// Small circular pencil badge, styled to match the camera capture badge —
/// tap to open the full-size edit dialog for this reading.
class EditBadge extends StatelessWidget {
  final VoidCallback onTap;
  final double size;
  const EditBadge({super.key, required this.onTap, this.size = 28});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.ink800,
          border: Border.all(color: AppColors.ink900, width: 2),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4)],
        ),
        child: Icon(Icons.edit, size: size * 0.5, color: AppColors.cyan),
      ),
    );
  }
}
