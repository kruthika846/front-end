import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/entry_form_provider.dart';
import '../theme/app_colors.dart';

/// Whether a person has checked this value (design: "a person checks every value"). Typed
/// values count as checked; a value an HMI scan or gauge reading filled in shows amber until
/// the person compares it with the instrument and taps it. Empty values show nothing.
class CheckTick extends ConsumerWidget {
  final String paramKey;
  final double size;
  const CheckTick({super.key, required this.paramKey, this.size = 20});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filled = ref.watch(entryFormProvider.select((s) => (s.values[paramKey] ?? '').trim().isNotEmpty));
    final checked = ref.watch(entryFormProvider.select((s) => s.isChecked(paramKey)));
    if (!filled) return SizedBox(width: size, height: size);
    return Tooltip(
      message: checked ? 'Checked' : 'From a photo - tap once you have compared it with the instrument',
      child: InkResponse(
        radius: size,
        onTap: () => ref.read(entryFormProvider.notifier).setChecked(paramKey, !checked),
        child: Icon(
          checked ? Icons.check_circle : Icons.error_outline,
          size: size,
          color: checked ? AppColors.good : AppColors.gold,
        ),
      ),
    );
  }
}
