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
  required int generatorNumber,
}) async {
  final units = {for (final p in remoteParams) p.key: p.unit};
  var readings = confidentReadings(result, generatorNumber: generatorNumber, unitOfParam: units);
  final labelFor = {for (final p in remoteParams) p.key: p.label};
  final where = switch (result.source) {
    'DSR Extract on this tablet' => 'Read by DSR Extract on this tablet (no server needed). ',
    'this tablet' => 'Read on this tablet with the simpler reader (${result.fallbackReason ?? 'DSR Extract not reachable'}). ',
    _ => 'Read by DSR Extract. ',
  };

  // The screen in the photo is another generator's (e.g. Generator no.3's screen photographed for a
  // Generator 2 entry): its values are never put in this entry silently. Say so and let the
  // operator retake the photo or knowingly use them.
  int? fromGenerator;
  final named = generatorsInPhoto(result);
  if (named.isNotEmpty && !named.contains(generatorNumber)) {
    final other = (named.toList()..sort()).first;
    final theirs = confidentReadings(result, generatorNumber: generatorNumber, unitOfParam: units, useGeneratorOfPhoto: other);
    if (theirs.isNotEmpty) {
      if (!context.mounted) return;
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('This photo shows Generator $other'),
          content: Text(
            '${where}This entry is for Generator $generatorNumber, but the screen in the photo is Generator no.$other '
            '(${theirs.length} reading(s)).'
            '${readings.isNotEmpty ? ' Only ${readings.length} unnamed value(s) in the photo could be Generator $generatorNumber\'s.' : ''}\n\n'
            'Retake the photo on Generator $generatorNumber\'s screen, or use Generator $other\'s values only if that is '
            'really what you mean to log here.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Retake / cancel')),
            if (readings.isNotEmpty)
              TextButton(onPressed: () => Navigator.pop(ctx, 'mine'), child: Text('Use Generator $generatorNumber\'s part')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'other'), child: Text('Use Generator $other\'s values')),
          ],
        ),
      );
      if (choice == null) return;
      if (choice == 'other') {
        readings = theirs;
        fromGenerator = other;
      }
    }
  }

  if (readings.isEmpty) {
    if (!context.mounted) return;
    final seen = result.values.take(8).map((v) => '• ${v.label} = ${v.value} ${v.unit ?? ''}'.trim()).join('\n');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No matching readings found'),
        content: SingleChildScrollView(
          child: Text(
            '${where}OCR found ${result.values.length} value(s) in this photo, but none of them matched a field of '
            'Generator $generatorNumber that this app knows how to auto-fill. Enter values by hand as usual.'
            '${seen.isEmpty ? '' : '\n\nWhat was read:\n$seen${result.values.length > 8 ? '\n…' : ''}'}',
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
    return;
  }

  // A value not marked as this generator's on the photo starts unticked (see confidentReadings).
  final selected = {for (final r in readings) r.paramKey: !r.uncertain};
  final placedLabels = {for (final r in readings) r.ocrLabel};
  final unplaced = result.values.where((v) => !placedLabels.contains(v.label)).toList();

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
                  '${where}Recognized ${readings.length} of ${result.values.length} value(s) as Generator $generatorNumber fields'
                  '${fromGenerator != null ? ' — taken from Generator $fromGenerator\'s screen, as you chose' : ''}. '
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
                    subtitle: Text(
                      '${r.value} ${r.unit}  ·  read as "${r.ocrLabel}"${r.converted ? '  ·  unit converted' : ''}'
                      '${r.uncertain ? '\nNot marked as Generator $generatorNumber on the photo — tick only if it is' : ''}',
                      style: r.uncertain ? const TextStyle(color: AppColors.gold) : null,
                    ),
                    onChanged: (v) => setState(() => selected[r.paramKey] = v ?? false),
                  ),
                // Everything else that was read: shows why a field stayed empty (another
                // generator's block, a label the app doesn't know, a status word, ...).
                if (unplaced.isNotEmpty)
                  Theme(
                    data: Theme.of(ctx).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(
                        'Also read, not filled in (${unplaced.length})',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                      ),
                      children: [
                        for (final v in unplaced)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '${v.label} = ${v.value} ${v.unit ?? ''}'.trim(),
                                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                              ),
                            ),
                          ),
                      ],
                    ),
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
      notifier.setReaderValue(r.paramKey, r.value); // unchecked until a person ticks it
      count++;
    }
  }

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Applied $count value(s) from OCR. Each shows an amber tick until you check it against the screen.')),
    );
  }
}
