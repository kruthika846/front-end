import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/param_definition.dart';
import '../providers/entry_form_provider.dart';
import '../services/ocr_field_mapping.dart';
import '../services/ocr_service.dart';
import '../theme/app_colors.dart';

/// Shown right after an HMI screen photo is scanned — lets the operator
/// see exactly what OCR read before anything touches the form. Nothing is
/// applied automatically: every field is opt-in (checked by default, but
/// reviewable and uncheckable), and every value can still be edited by
/// hand afterward exactly like before this integration existed.
Future<void> showOcrReviewDialog(
  BuildContext context,
  WidgetRef ref, {
  required OcrScanResult result,
  required List<ParamDefinition> remoteParams,
}) async {
  final readings = confidentReadings(result);
  final labelFor = {for (final p in remoteParams) p.key: p.label};
  // result.readingCount is OCR's total raw text-block count for the whole
  // photo (labels, stray marks, everything) — comparing "readings.length"
  // against that made the ratio look alarming for no reason. The number
  // that actually matters is how many *schema fields* got a real value
  // this scan, regardless of whether this app knows how to map them yet.
  final matchedFieldCount = result.fields.where((f) => f.found).length;

  if (readings.isEmpty) {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No matching readings found'),
        content: Text(
          'OCR found $matchedFieldCount value(s) in this photo, but none of them matched a field this app '
          'knows how to auto-fill yet. Enter values by hand as usual.',
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
    return;
  }

  final selected = {for (final r in readings) r.paramKey: true};

  if (!context.mounted) return;
  final applied = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Review OCR readings'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recognized ${readings.length} of ${result.readingCount} scanned value(s) against known fields. '
                  'Uncheck anything you don\'t want filled in — every value stays editable by hand after applying.',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                ),
                const SizedBox(height: 12),
                for (final r in readings)
                  CheckboxListTile(
                    value: selected[r.paramKey],
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(labelFor[r.paramKey] ?? r.paramKey),
                    subtitle: Text('${r.value} ${r.unit}  ·  read as "${r.ocrLabel}"'),
                    onChanged: (v) => setState(() => selected[r.paramKey] = v ?? false),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Discard')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apply Selected')),
        ],
      ),
    ),
  );

  if (applied != true) return;

  final notifier = ref.read(entryFormProvider.notifier);
  var count = 0;
  for (final r in readings) {
    if (selected[r.paramKey] == true) {
      notifier.setValue(r.paramKey, r.value);
      count++;
    }
  }

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Applied $count value(s) from OCR — review them on the form before submitting.')),
    );
  }
}
