import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../models/logbook_entry.dart';
import '../models/param_definition.dart';
import '../providers/entry_form_provider.dart';
import '../providers/history_provider.dart';
import '../providers/repository_providers.dart';
import '../theme/app_colors.dart';
import '../widgets/dynamic_param_field.dart';
import '../widgets/edit_value_dialog.dart';
import '../widgets/engine_diagram.dart';
import '../widgets/gauge_dial.dart';
import '../widgets/panel_comment_field.dart';
import '../widgets/photo_upload_field.dart';
import '../widgets/signature_pad_field.dart';

class EntryFormScreen extends ConsumerStatefulWidget {
  final int generatorNumber;
  const EntryFormScreen({super.key, required this.generatorNumber});

  @override
  ConsumerState<EntryFormScreen> createState() => _EntryFormScreenState();
}

class _EntryFormScreenState extends ConsumerState<EntryFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // Generated once per screen visit so photo/signature files for this draft
  // share a stable name, even before the entry is actually saved.
  late final String _entryId = DateTime.now().microsecondsSinceEpoch.toString();

  Future<void> _submit(List<ParamDefinition> remoteParams, List<ParamDefinition> localParams) async {
    final formOk = _formKey.currentState?.validate() ?? false;
    final formState = ref.read(entryFormProvider);

    if (!formOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in every required field correctly')),
      );
      return;
    }

    if (formState.readingSlot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select Time or Noon before submitting')),
      );
      return;
    }

    if (formState.signaturePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signature is required before submitting')),
      );
      return;
    }

    final categoryByKey = <String, ParamCategory>{
      for (final p in remoteParams) p.key: ParamCategory.remote,
      for (final p in localParams) p.key: ParamCategory.local,
    };

    final entry = LogbookEntry(
      id: _entryId,
      engineId: 'Aux Engine ${widget.generatorNumber} Local Start-Stop Panel',
      generatorNumber: widget.generatorNumber,
      readingSlot: formState.readingSlot,
      timestamp: DateTime.now(),
      notes: formState.notes,
      signaturePath: formState.signaturePath,
      photoPath: formState.photoPath,
      pdfPath: formState.pdfPath,
      hmiPhotoPath: formState.hmiPhotoPath,
      paramValues: formState.values,
      paramPhotos: formState.paramPhotos,
    );

    await ref.read(logbookRepositoryProvider).saveEntry(entry, categoryByKey: categoryByKey);
    ref.read(entryFormProvider.notifier).reset();
    ref.invalidate(recentEntriesProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entry saved locally')),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(parameterConfigProvider);

    return Scaffold(
      appBar: AppBar(title: Text('New Entry — Generator ${widget.generatorNumber}')),
      body: configAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Failed to load parameters: $e')),
        data: (config) {
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                const _ReadingSlotSelector(),
                const SizedBox(height: 16),
                _RemoteParametersPanel(remoteParams: config.remoteParams, entryId: _entryId),
                const SizedBox(height: 16),
                _LocalParametersPanel(localParams: config.localParams, entryId: _entryId),
                const SizedBox(height: 16),
                _Section(
                  icon: Icons.notes,
                  title: 'Notes',
                  children: [
                    TextFormField(
                      maxLines: 3,
                      decoration: const InputDecoration(hintText: 'Optional — anything worth flagging'),
                      onChanged: (v) => ref.read(entryFormProvider.notifier).setNotes(v),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _Section(
                  icon: Icons.picture_as_pdf_outlined,
                  title: 'Documents',
                  children: [PhotoUploadField(entryId: _entryId, showLabel: false)],
                ),
                const SizedBox(height: 16),
                _Section(
                  icon: Icons.draw_outlined,
                  title: 'Operator Signature',
                  children: [SignaturePadField(entryId: _entryId, showLabel: false)],
                ),
                const SizedBox(height: 28),
                _SubmitButton(onPressed: () => _submit(config.remoteParams, config.localParams)),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Explicit Time/Noon selector — which of the day's two paper-log columns
/// this entry is for. The operator picks this instead of the app guessing
/// from the clock, so a reading taken late still lands in the right column.
class _ReadingSlotSelector extends ConsumerWidget {
  const _ReadingSlotSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slot = ref.watch(entryFormProvider.select((s) => s.readingSlot));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.access_time, color: AppColors.cyan, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Reading Time',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<String>(
                initialValue: slot,
                decoration: const InputDecoration(hintText: 'Select'),
                items: const [
                  DropdownMenuItem(value: 'time', child: Text('Time')),
                  DropdownMenuItem(value: 'noon', child: Text('Noon')),
                ],
                validator: (v) => v == null ? 'Required' : null,
                onChanged: (v) {
                  if (v != null) ref.read(entryFormProvider.notifier).setReadingSlot(v);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The whole "Remote Parameters" area: a big Load readout, the engine
/// schematic (turbo + cylinders + mean temp), then the remaining systems
/// as color-coded chip groups, and the alarm indicators as LEDs.
class _RemoteParametersPanel extends StatelessWidget {
  final List<ParamDefinition> remoteParams;
  final String entryId;

  const _RemoteParametersPanel({required this.remoteParams, required this.entryId});

  ParamDefinition _find(String key) => remoteParams.firstWhere((p) => p.key == key);

  @override
  Widget build(BuildContext context) {
    final byGroup = <String, List<ParamDefinition>>{};
    for (final p in remoteParams) {
      byGroup.putIfAbsent(p.group ?? 'Other', () => []).add(p);
    }

    final load = remoteParams.where((p) => p.group == 'Generator Output').toList();
    final cylinders = List.generate(6, (i) => _find('exh_temp_cyl${i + 1}'));

    final chipGroups = <_ChipGroup>[
      if (byGroup['Lubrication & Cooling'] != null)
        _ChipGroup('Lubrication & Cooling', byGroup['Lubrication & Cooling']!, AppColors.teal),
      if (byGroup['Alternator'] != null) _ChipGroup('Alternator', byGroup['Alternator']!, AppColors.gold),
    ];
    final statusParams = byGroup['Status Indicators'] ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.satellite_alt, color: AppColors.cyan, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Remote Parameters',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            _HmiCaptureButton(entryId: entryId),
          ],
        ),
        const SizedBox(height: 14),
        if (load.isNotEmpty) ...[
          _LoadReadout(definition: load.first),
          const SizedBox(height: 10),
          PanelCommentField(groupKey: 'remote::${load.first.group}'),
        ],
        const SizedBox(height: 14),
        EngineDiagram(
          turboInlet: _find('tc_inlet_temp'),
          turboOutlet: _find('tc_outlet_temp'),
          mean: _find('exh_temp_mean'),
          cylinders: cylinders,
        ),
        const SizedBox(height: 20),
        for (final group in chipGroups) ...[
          _GroupLabel(text: group.title, color: group.color),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: group.params.map((p) => DynamicParamField(definition: p, compact: true, accent: group.color)).toList(),
          ),
          const SizedBox(height: 10),
          PanelCommentField(groupKey: 'remote::${group.title}'),
          const SizedBox(height: 18),
        ],
        if (statusParams.isNotEmpty) ...[
          const _GroupLabel(text: 'Status Indicators', color: AppColors.textMuted),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: statusParams.map((p) => DynamicParamField(definition: p)).toList(),
          ),
          const SizedBox(height: 10),
          const PanelCommentField(groupKey: 'remote::Status Indicators'),
        ],
      ],
    );
  }
}

/// One photo of the whole remote HMI/monitoring screen — evidence of what
/// the display showed at the time these values were transcribed. This does
/// NOT read the values automatically; the operator still types every
/// remote parameter in by hand, same as before. Auto-extracting numbers
/// from the photo would need real computer vision/OCR — out of scope here.
class _HmiCaptureButton extends ConsumerWidget {
  final String entryId;
  const _HmiCaptureButton({required this.entryId});

  Future<void> _capture(BuildContext context, WidgetRef ref) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 90);
    if (picked == null) return;

    final dir = await getApplicationDocumentsDirectory();
    final targetDir = Directory('${dir.path}/hmi_photos');
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    final ext = picked.path.split('.').last;
    final targetPath = '${targetDir.path}/$entryId.$ext';
    await File(picked.path).copy(targetPath);

    ref.read(entryFormProvider.notifier).setHmiPhotoPath(targetPath);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('HMI screen photo saved')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPhoto = ref.watch(entryFormProvider.select((s) => s.hmiPhotoPath != null));

    return OutlinedButton.icon(
      onPressed: () => _capture(context, ref),
      style: OutlinedButton.styleFrom(
        foregroundColor: hasPhoto ? AppColors.good : AppColors.cyan,
        side: BorderSide(color: hasPhoto ? AppColors.good : AppColors.cyan),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      icon: Icon(hasPhoto ? Icons.check_circle : Icons.camera_alt, size: 16),
      label: Text(hasPhoto ? 'HMI Captured' : 'Capture HMI Screen', style: const TextStyle(fontSize: 12)),
    );
  }
}

class _ChipGroup {
  final String title;
  final List<ParamDefinition> params;
  final Color color;
  _ChipGroup(this.title, this.params, this.color);
}

class _GroupLabel extends StatelessWidget {
  final String text;
  final Color color;
  const _GroupLabel({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 3, height: 13, color: color.withValues(alpha: 0.6)),
        const SizedBox(width: 7),
        Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                letterSpacing: 0.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
              ),
        ),
      ],
    );
  }
}

/// The whole "Local Parameters" area — the 30 manually-read gauge values
/// grouped the way an operator would actually walk the engine room: the two
/// six-unit banks (JCW / exhaust outlet temps) collapse into dropdowns like
/// the cylinder bank, everything else sits in labeled color-coded clusters.
class _LocalParametersPanel extends StatelessWidget {
  final List<ParamDefinition> localParams;
  final String entryId;

  const _LocalParametersPanel({required this.localParams, required this.entryId});

  @override
  Widget build(BuildContext context) {
    final byGroup = <String, List<ParamDefinition>>{};
    for (final p in localParams) {
      byGroup.putIfAbsent(p.group ?? 'Other', () => []).add(p);
    }

    final expandableGroups = <_ChipGroup>[
      if (byGroup['JCW Outlet Temp'] != null) _ChipGroup('JCW Outlet Temp', byGroup['JCW Outlet Temp']!, AppColors.teal),
      if (byGroup['Exhaust Outlet Temp'] != null) _ChipGroup('Exhaust Outlet Temp', byGroup['Exhaust Outlet Temp']!, AppColors.gold),
    ];
    final plainGroups = <_ChipGroup>[
      if (byGroup['Lubrication'] != null) _ChipGroup('Lubrication', byGroup['Lubrication']!, AppColors.teal),
      if (byGroup['Cooling Water'] != null) _ChipGroup('Cooling Water', byGroup['Cooling Water']!, AppColors.cyan),
      if (byGroup['Charge Air & Turbocharger'] != null)
        _ChipGroup('Charge Air & Turbocharger', byGroup['Charge Air & Turbocharger']!, AppColors.gold),
      if (byGroup['Fuel & Starting Air'] != null) _ChipGroup('Fuel & Starting Air', byGroup['Fuel & Starting Air']!, AppColors.cyan),
      if (byGroup['Generator & Running Data'] != null)
        _ChipGroup('Generator & Running Data', byGroup['Generator & Running Data']!, AppColors.teal),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.build_circle_outlined, color: Theme.of(context).colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Local Parameters',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (final group in expandableGroups) ...[
              _ExpandableChipGroup(group: group, entryId: entryId),
              const SizedBox(height: 12),
            ],
            for (final group in plainGroups) ...[
              _GroupLabel(text: group.title, color: group.color),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 14,
                children: group.params.map((p) => GaugeDial(definition: p, accent: group.color, entryId: entryId)).toList(),
              ),
              const SizedBox(height: 10),
              PanelCommentField(groupKey: 'local::${group.title}'),
              const SizedBox(height: 18),
            ],
          ],
        ),
      ),
    );
  }
}

/// A collapsible "N/M filled" dropdown for a chip group — same pattern as
/// the engine diagram's Cylinder Bank, reused here for the two 6-unit banks
/// so 12 fields don't dominate the top of the Local Parameters card.
class _ExpandableChipGroup extends ConsumerWidget {
  final _ChipGroup group;
  final String entryId;

  const _ExpandableChipGroup({required this.group, required this.entryId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final values = ref.watch(entryFormProvider.select((s) => s.values));
    final filledCount = group.params.where((p) => (values[p.key] ?? '').isNotEmpty).length;
    final allFilled = filledCount == group.params.length;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.ink900.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: group.color.withValues(alpha: 0.22)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: Material(
          type: MaterialType.transparency,
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
            iconColor: group.color,
            collapsedIconColor: group.color,
            title: Row(
              children: [
                Text(
                  group.title.toUpperCase(),
                  style: TextStyle(color: group.color, fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 0.8),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: allFilled ? AppColors.good.withValues(alpha: 0.18) : AppColors.textFaint.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$filledCount/${group.params.length}',
                    style: TextStyle(
                      color: allFilled ? AppColors.good : AppColors.textMuted,
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 14,
                children: group.params.map((p) => GaugeDial(definition: p, accent: group.color, entryId: entryId)).toList(),
              ),
              const SizedBox(height: 12),
              PanelCommentField(groupKey: 'local::${group.title}'),
            ],
          ),
        ),
      ),
    );
  }
}

/// The generator's headline number — Load in kW — shown the way the real
/// panel shows "432 kW" next to the generator name: big, unmissable.
class _LoadReadout extends ConsumerWidget {
  final ParamDefinition definition;
  const _LoadReadout({required this.definition});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(entryFormProvider.select((s) => s.values[definition.key] ?? ''));
    final notifier = ref.read(entryFormProvider.notifier);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppColors.blue.withValues(alpha: 0.22), AppColors.cyan.withValues(alpha: 0.10)]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.blue.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bolt, color: AppColors.cyan, size: 26),
          const SizedBox(width: 10),
          const Text('LOAD', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700, letterSpacing: 1)),
          const Spacer(),
          SizedBox(
            width: 90,
            child: TextFormField(
              initialValue: value,
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 30),
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
          const SizedBox(width: 6),
          const Padding(
            padding: EdgeInsets.only(bottom: 3),
            child: Text('kW', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600, fontSize: 15)),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.edit, size: 16),
            color: AppColors.cyan,
            visualDensity: VisualDensity.compact,
            onPressed: () => showEditValueDialog(context, ref, definition),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const _Section({required this.icon, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// A bold pill-shaped "commit" control instead of a plain rectangular
/// button — this is the one irreversible action on the screen, it should
/// look like it.
class _SubmitButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _SubmitButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          height: 58,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppColors.blue, AppColors.cyan]),
            borderRadius: BorderRadius.circular(999),
            boxShadow: [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8))],
          ),
          child: const Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 22),
                SizedBox(width: 10),
                Text(
                  'SUBMIT ENTRY',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: 0.6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
