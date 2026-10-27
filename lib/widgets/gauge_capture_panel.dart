import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../models/param_definition.dart';
import '../providers/entry_form_provider.dart';
import '../services/device_ocr.dart';
import '../services/units.dart';
import '../theme/app_colors.dart';

/// Local Parameters' gauge capture: ONE round capture button for every kind of
/// gauge. Each photo is read on the tablet by gauge-reader and gets its own result
/// card — the marked-up photo, the reading, how sure the reader is, scale, needle,
/// notes — with a "Save to" choice of which parameter it goes into. Nothing is
/// filled in until the operator taps Save reading.
class GaugeCapturePanel extends ConsumerStatefulWidget {
  final List<ParamDefinition> localParams;
  final String entryId;

  const GaugeCapturePanel({super.key, required this.localParams, required this.entryId});

  @override
  ConsumerState<GaugeCapturePanel> createState() => _GaugeCapturePanelState();
}

class _Capture {
  final int n;
  final String photoPath;
  final String debugPath;
  GaugeReading? reading; // null while it is being read
  String? targetKey;
  String? savedKey;

  _Capture({required this.n, required this.photoPath, required this.debugPath});
}

class _GaugeCapturePanelState extends ConsumerState<GaugeCapturePanel> {
  final _captures = <_Capture>[]; // newest first
  int _count = 0;

  List<ParamDefinition> get _numberParams =>
      widget.localParams.where((p) => p.inputType == ParamInputType.number).toList();

  Future<void> _capture({_Capture? replacing}) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 90, maxWidth: 2400, maxHeight: 2400);
    if (picked == null) return;
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/gauge_photos');
    if (!await dir.exists()) await dir.create(recursive: true);
    final n = ++_count;
    final base = '${dir.path}/${widget.entryId}_gauge$n';
    final photo = '$base.jpg';
    await File(picked.path).copy(photo);

    final c = _Capture(n: n, photoPath: photo, debugPath: '${base}_marked.jpg');
    setState(() {
      final at = replacing == null ? -1 : _captures.indexOf(replacing);
      if (at >= 0) {
        _captures[at] = c;
      } else {
        _captures.insert(0, c);
      }
    });

    final r = await DeviceOcr.readGauge(photo, debugPath: c.debugPath);
    if (!mounted) return;
    setState(() {
      c.reading = r;
      c.targetKey = _guessTarget(r);
    });
  }

  /// The parameter this gauge most likely is: same kind of unit (a pressure gauge only
  /// goes into pressures), best match between its name plate and the parameter's name,
  /// otherwise the first such parameter still empty.
  String? _guessTarget(GaugeReading r) {
    if (r.error != null) return null;
    final fits = _compatible(r);
    if (fits.isEmpty) return null;
    final plate = _words(r.display['label'] ?? '');
    int score(ParamDefinition p) => _words('${p.label} ${p.group ?? ''}').intersection(plate).length;
    final best = fits.reduce((a, b) => score(b) > score(a) ? b : a);
    if (score(best) > 0) return best.key;
    final values = ref.read(entryFormProvider).values;
    return fits.firstWhere((p) => (values[p.key] ?? '').isEmpty, orElse: () => fits.first).key;
  }

  List<ParamDefinition> _compatible(GaugeReading r) {
    final kind = unitKind(r.unit);
    final fits = _numberParams.where((p) => unitKind(p.unit) == kind).toList();
    return fits.isEmpty ? _numberParams : fits;
  }

  /// Name-plate words in the parameters' own short forms ("FUEL OIL PRESSURE" -> fo).
  static Set<String> _words(String s) {
    var t = ' ${s.toLowerCase()} ';
    for (final (re, to) in [
      (RegExp(r'lub(?:e|ricating)?\.?\s*oil'), ' lo '),
      (RegExp(r'fuel\s*oil'), ' fo '),
      (RegExp(r'jacket\s*(?:cooling\s*)?water'), ' jcw '),
      (RegExp(r'high\s*temp\w*'), ' ht '),
      (RegExp(r'low\s*temp\w*'), ' lt '),
      (RegExp(r'cool(?:ing)?\s*water'), ' cw '),
      (RegExp(r'charge\s*air'), ' charge '),
      (RegExp(r'start(?:ing)?\s*air'), ' starting '),
      (RegExp(r'turbo\s*charger'), ' tc '),
    ]) {
      t = t.replaceAll(re, to);
    }
    const generic = {'press', 'pressure', 'temp', 'temperature', 'gauge', 'pi', 'ti', 'no', 'the', 'of', 'and', 'inlet', 'in', 'outlet', 'out', 'sys', 'system'};
    // single digits count: "Unit No.2" must pick Unit 2, not Unit 1
    return t.split(RegExp(r'[^a-z0-9]+')).where((w) => (w.length > 1 || RegExp(r'\d').hasMatch(w)) && !generic.contains(w)).toSet();
  }

  void _save(_Capture c) {
    final r = c.reading!;
    final p = _numberParams.firstWhere((p) => p.key == c.targetKey);
    final v = convertUnit(r.value!, r.unit, p.unit) ?? r.value!;
    final places = v.abs() < 10 ? 3 : 1;
    final value = double.parse(v.toStringAsFixed(places)).toString();
    final notifier = ref.read(entryFormProvider.notifier);
    notifier.setReaderValue(p.key, value); // unchecked until a person ticks it
    notifier.setParamPhoto(p.key, c.photoPath);
    setState(() => c.savedKey = p.key);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved $value ${p.unit} to ${p.label} (${p.group ?? 'Local'})')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: _CaptureCircle(onTap: () => _capture())),
        const SizedBox(height: 6),
        const Center(
          child: Text(
            'One button for every gauge — photograph it, check the reading, choose where it goes',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ),
        for (final c in _captures) ...[
          const SizedBox(height: 16),
          _CaptureCard(
            capture: c,
            targets: c.reading == null || c.reading!.error != null ? const [] : _compatible(c.reading!),
            onTarget: (k) => setState(() => c.targetKey = k),
            onRetake: () => _capture(replacing: c),
            onSave: () => _save(c),
            onRemove: () => setState(() => _captures.remove(c)),
          ),
        ],
      ],
    );
  }
}

/// The single round "capture a gauge" control.
class _CaptureCircle extends StatelessWidget {
  final VoidCallback onTap;
  const _CaptureCircle({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 132,
        height: 132,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFF3A5680), Color(0xFF22344F)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          border: Border.all(color: AppColors.cyan.withValues(alpha: 0.7), width: 3),
          boxShadow: [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.25), blurRadius: 18)],
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.camera_alt, color: AppColors.cyan, size: 38),
            SizedBox(height: 6),
            Text('Capture gauge', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

/// One capture's result, laid out like gauge-reader's own result page: the marked-up
/// photo, the reading, a confidence badge, the details, then Retake / Save reading.
class _CaptureCard extends StatelessWidget {
  final _Capture capture;
  final List<ParamDefinition> targets;
  final ValueChanged<String?> onTarget;
  final VoidCallback onRetake;
  final VoidCallback onSave;
  final VoidCallback onRemove;

  const _CaptureCard({
    required this.capture,
    required this.targets,
    required this.onTarget,
    required this.onRetake,
    required this.onSave,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final r = capture.reading;
    final marked = File(capture.debugPath);
    final picture = r != null && marked.existsSync() ? marked : File(capture.photoPath);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.ink900.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.ink600),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              GestureDetector(
                onTap: () => _showPicture(context, picture),
                child: Image.file(picture, height: 280, fit: BoxFit.cover, key: ValueKey(picture.path)),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: IconButton.filledTonal(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Remove this capture',
                  onPressed: onRemove,
                ),
              ),
              Positioned(
                left: 10,
                top: 10,
                child: _Pill(text: 'Gauge ${capture.n}', color: AppColors.cyan),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            child: r == null
                ? const Row(
                    children: [
                      SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 12),
                      Expanded(child: Text('Reading the gauge on this tablet…', style: TextStyle(color: AppColors.textMuted))),
                    ],
                  )
                : r.error != null
                    ? _error(r)
                    : _result(context, r),
          ),
        ],
      ),
    );
  }

  Widget _error(GaugeReading r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Could not read this gauge', style: TextStyle(color: AppColors.alarm, fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 6),
        Text('${r.error}. Retake it closer and straighter, or type the value in its parameter below.',
            style: const TextStyle(color: AppColors.textMuted)),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onRetake, child: const Text('Retake')),
      ],
    );
  }

  Widget _result(BuildContext context, GaugeReading r) {
    final d = r.display;
    final pct = (r.confidence * 100).round();
    final sure = r.confidence >= 0.6;
    final saved = capture.savedKey != null && capture.savedKey == capture.targetKey;
    final target = targets.where((p) => p.key == capture.targetKey).firstOrNull;
    final converted = target == null ? null : convertUnit(r.value!, r.unit, target.unit);
    final showsConversion = target != null && converted != null && unitKind(target.unit) == unitKind(r.unit) &&
        target.unit.replaceAll('°', '') != r.unit.replaceAll('°', '');

    final rows = <(String, String)>[
      ('Label', d['label'] ?? ''),
      ('Gauge type', d['type'] ?? ''),
      ('Reading', d['reading'] ?? ''),
      ('Confidence', d['confidence'] ?? ''),
      if (d['second_scale'] != null) ('2nd scale', d['second_scale']!),
      if (d['also'] != null) ('Also', d['also']!),
      if (d['scale'] != null) ('Scale', d['scale']!),
      if (d['needle'] != null) ('Needle', d['needle']!),
      if (d['gauge_at'] != null) ('Gauge at', d['gauge_at']!),
      ('Time', d['time'] ?? ''),
      ('Status', d['status'] ?? r.status),
      if (r.gaugesFound > 1) ('Gauges', '${r.gaugesFound} in the photo — the clearest one was read'),
      for (final n in r.notes) ('Note', n),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(d['label'] ?? 'Gauge', style: const TextStyle(color: AppColors.textMuted, fontSize: 14)),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(_number(d['reading'] ?? '${r.value}'),
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 40, fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            Text(d['unit'] ?? r.unit, style: const TextStyle(color: AppColors.textMuted, fontSize: 22, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 6),
        _Pill(text: sure ? 'Looks right ($pct%)' : 'Check the picture ($pct%)', color: sure ? AppColors.good : AppColors.gold),
        const Divider(height: 26, color: AppColors.ink600),
        for (final (k, v) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 110, child: Text(k, style: const TextStyle(color: AppColors.textMuted))),
                Expanded(child: Text(v, style: const TextStyle(color: AppColors.textPrimary))),
              ],
            ),
          ),
        const Divider(height: 26, color: AppColors.ink600),
        const Text('Save to', style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
        const SizedBox(height: 4),
        DropdownButton<String>(
          value: capture.targetKey,
          isExpanded: true,
          hint: const Text('Choose the parameter this gauge is'),
          items: [
            for (final p in targets)
              DropdownMenuItem(
                value: p.key,
                child: Text('${p.label}  ·  ${p.group ?? ''}  (${p.unit})', overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onTarget,
        ),
        if (showsConversion)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Saved as ${double.parse(converted.toStringAsFixed(converted.abs() < 10 ? 3 : 1))} ${target.unit} (converted from ${r.unit})',
              style: const TextStyle(color: AppColors.gold, fontSize: 12),
            ),
          ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 50)),
                onPressed: onRetake,
                child: const Text('Retake'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 50),
                  backgroundColor: saved ? AppColors.good : AppColors.blue,
                ),
                onPressed: capture.targetKey == null ? null : onSave,
                child: Text(saved ? 'Saved ✓' : 'Save reading'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// "1.089 MPa" -> "1.089"
  static String _number(String reading) => reading.split(' ').first;

  void _showPicture(BuildContext context, File picture) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: InteractiveViewer(maxScale: 6, child: Image.file(picture)),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.8)),
      ),
      child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
    );
  }
}
