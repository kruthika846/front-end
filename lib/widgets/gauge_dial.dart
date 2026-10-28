import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../models/param_definition.dart';
import '../providers/entry_form_provider.dart';
import '../services/device_ocr.dart';
import '../theme/app_colors.dart';
import 'check_tick.dart';
import 'edit_value_dialog.dart';
import 'synced_text_field.dart';

/// A circular, gauge-styled reading for Local Parameters: a radial fill
/// ring showing where the typed value sits in its min/max range (like a
/// real dial), the number entered in the center, and a camera badge for
/// photographing the physical gauge. The photo is kept as evidence and read
/// on the tablet by gauge-reader, which offers the value; the operator
/// applies it (or types the number) themselves.
class GaugeDial extends ConsumerWidget {
  final ParamDefinition definition;
  final Color accent;
  final String entryId;

  const GaugeDial({super.key, required this.definition, required this.accent, required this.entryId});

  Future<String> _copyToAppStorage(String sourcePath, String subDir, String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final targetDir = Directory('${dir.path}/$subDir');
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    final targetPath = '${targetDir.path}/$fileName';
    await File(sourcePath).copy(targetPath);
    return targetPath;
  }

  Future<void> _capturePhoto(BuildContext context, WidgetRef ref) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (picked == null) return;
    final ext = picked.path.split('.').last;
    final savedPath = await _copyToAppStorage(picked.path, 'gauge_photos', '${entryId}_${definition.key}.$ext');
    ref.read(entryFormProvider.notifier).setParamPhoto(definition.key, savedPath);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Gauge photo saved for ${definition.label} — reading the dial on this tablet...')),
    );
    await _readGauge(context, ref, savedPath);
  }

  /// Reads the photographed needle gauge with gauge-reader, on this tablet,
  /// and offers the value. Like HMI scans, nothing is filled in until the
  /// operator applies it, and it stays editable by hand.
  Future<void> _readGauge(BuildContext context, WidgetRef ref, String photoPath) async {
    final r = await DeviceOcr.readGauge(photoPath, unit: definition.unit);
    if (!context.mounted) return;
    if (r.error != null || r.value == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not read this gauge (${r.error ?? 'no value found'}). Type the value as usual.')),
      );
      return;
    }
    // Pressures in MPa need more places than temperatures in °C.
    final read = r.valueInWantedUnit ?? r.value!;
    final places = read.abs() < 10 ? 2 : 1;
    final value = double.parse(read.toStringAsFixed(places)).toString();
    final apply = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Gauge reading — ${definition.label}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$value ${definition.unit}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'Read on this tablet · confidence ${(r.confidence * 100).round()}%'
              '${r.converted ? '\nThe dial shows ${r.value} ${r.unit}; converted to ${definition.unit}.' : ''}'
              '${r.gaugesFound > 1 ? '\n${r.gaugesFound} gauges in the photo; the clearest one was read.' : ''}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
            ),
            for (final n in r.notes.take(3))
              Text('• $n', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 8),
            const Text('Check it against the dial before applying.', style: TextStyle(fontSize: 12.5)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Discard')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apply')),
        ],
      ),
    );
    // unchecked until a person ticks it against the dial
    if (apply == true) ref.read(entryFormProvider.notifier).setReaderValue(definition.key, value);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(entryFormProvider.select((s) => s.values[definition.key] ?? ''));
    final photoPath = ref.watch(entryFormProvider.select((s) => s.paramPhotos[definition.key]));
    final notifier = ref.read(entryFormProvider.notifier);
    final hasPhoto = photoPath != null;

    double fraction = 0;
    final parsed = double.tryParse(value);
    if (parsed != null && definition.min != null && definition.max != null && definition.max! > definition.min!) {
      fraction = ((parsed - definition.min!) / (definition.max! - definition.min!)).clamp(0.0, 1.0);
    }

    // Only surface a message once the operator has actually typed something
    // — an untouched blank field shouldn't flash red before they've had a
    // chance to fill it in. A submit attempt on a still-blank field is
    // caught separately by the form's overall validator. typeError can
    // still block Submit (not a real number); rangeWarning never does —
    // it's just a flag that this reading is outside the configured normal
    // range, so it's easy to spot and explain with a panel comment.
    final typeError = value.isEmpty ? null : definition.validateValue(value);
    final rangeWarning = definition.rangeWarning(value);
    final fieldError = typeError ?? rangeWarning;
    final ringColor = fieldError != null ? AppColors.alarm : accent;

    return SizedBox(
      width: 140,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 124,
            height: 124,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                SizedBox(
                  width: 124,
                  height: 124,
                  child: CircularProgressIndicator(
                    value: 1,
                    strokeWidth: 6,
                    color: AppColors.ink900.withValues(alpha: 0.5),
                  ),
                ),
                SizedBox(
                  width: 124,
                  height: 124,
                  child: CircularProgressIndicator(
                    value: fraction == 0 ? 0.001 : fraction,
                    strokeWidth: 6,
                    color: ringColor,
                    backgroundColor: Colors.transparent,
                  ),
                ),
                Container(
                  width: 98,
                  height: 98,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3A5680), Color(0xFF22344F)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    border: Border.all(color: ringColor.withValues(alpha: 0.5), width: 1.4),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 76,
                          child: SyncedTextField(
                            value: value,
                            textAlign: TextAlign.center,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 22),
                            decoration: const InputDecoration(
                              isCollapsed: true,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              errorStyle: TextStyle(fontSize: 0, height: 0),
                            ),
                            onChanged: (v) => notifier.setValue(definition.key, v),
                            validator: definition.validateValue,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(definition.unit, style: const TextStyle(color: AppColors.textFaint, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: () => _capturePhoto(context, ref),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hasPhoto ? AppColors.good : AppColors.ink800,
                        border: Border.all(color: AppColors.ink900, width: 2),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4)],
                      ),
                      child: Icon(
                        hasPhoto ? Icons.check : Icons.camera_alt,
                        size: 17,
                        color: hasPhoto ? Colors.white : AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  child: EditBadge(size: 34, onTap: () => showEditValueDialog(context, ref, definition)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  definition.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.2),
                ),
              ),
              const SizedBox(width: 4),
              CheckTick(paramKey: definition.key, size: 16),
            ],
          ),
          // Sits below the fixed-size dial rather than inside it, so a wrong
          // reading (out of range, or not a number) gets an actual visible
          // message instead of just silently failing at submit time.
          if (fieldError != null) ...[
            const SizedBox(height: 2),
            Text(
              fieldError,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.alarm, fontSize: 10.5, fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }
}
