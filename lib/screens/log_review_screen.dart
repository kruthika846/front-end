import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/session_provider.dart';
import '../services/signing_service.dart';
import '../services/sync_service.dart';
import '../theme/app_colors.dart';
import '../widgets/pin_dialog.dart';

/// One log as the server holds it, for the signer: every value with its unit and normal
/// range, what the reader read where the person changed it, and the photos - then sign it
/// with the PIN, or send it back with a reason.
class LogReviewScreen extends ConsumerStatefulWidget {
  final WaitingLog log;
  final Map<String, dynamic>? config;
  const LogReviewScreen({super.key, required this.log, this.config});

  @override
  ConsumerState<LogReviewScreen> createState() => _LogReviewScreenState();
}

class _LogReviewScreenState extends ConsumerState<LogReviewScreen> {
  Map<String, dynamic>? _d;
  String? _error;
  bool _busy = false;

  SigningService get _signing => SigningService(ref.read(sessionProvider)!);

  @override
  void initState() {
    super.initState();
    _signing.detail(widget.log.id).then((d) {
      if (mounted) setState(() => _d = d);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = '$e');
    });
  }

  void _done(String text) {
    ref.read(syncProvider.notifier).syncNow();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    Navigator.of(context).pop();
  }

  void _fail(SigningException e) {
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.alarm));
  }

  Future<void> _sign() async {
    final pin = await askSigningPin(context,
        title: 'Sign this log', message: '${widget.log.screenName} · ${roundLabel(widget.config, widget.log.logType, widget.log.round)}');
    if (pin == null) return;
    setState(() => _busy = true);
    try {
      await _signing.approve(widget.log.id, pin);
      if (mounted) _done('Signed. This log is now final.');
    } on SigningException catch (e) {
      if (mounted) _fail(e);
    }
  }

  Future<void> _sendBack() async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Send back'),
          content: SizedBox(
            width: 420,
            child: TextField(
              controller: reason,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Reason (the Duty Engineer sees it)'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: reason.text.trim().isEmpty ? null : () => Navigator.pop(ctx, true),
              child: const Text('Send back'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _signing.sendBack(widget.log.id, reason.text.trim());
      if (mounted) _done('Sent back to the Duty Engineer.');
    } on SigningException catch (e) {
      if (mounted) _fail(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Scaffold(
      appBar: AppBar(title: Text('${widget.log.screenName} · ${roundLabel(widget.config, widget.log.logType, widget.log.round)}')),
      body: d == null
          ? Center(
              child: _error != null
                  ? Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: AppColors.gold)))
                  : const CircularProgressIndicator(),
            )
          : _body(d),
      bottomNavigationBar: d == null || d['status'] != 'submitted'
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
                        onPressed: _busy ? null : _sendBack,
                        icon: const Icon(Icons.reply),
                        label: const Text('Send back'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                        onPressed: _busy ? null : _sign,
                        icon: const Icon(Icons.draw),
                        label: const Text('Sign with PIN'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _body(Map<String, dynamic> d) {
    final readings = {for (final r in (d['readings'] as List)) r['data_point_id']: r};
    final points = [for (final p in (d['data_points'] as List)) if (readings[p['id']]?['value'] != null) p];
    final photos = (d['photos'] as List).cast<Map>();
    final when = d['submitted_at'] == null ? '' : DateFormat('dd MMM HH:mm').format(DateTime.parse('${d['submitted_at']}').toLocal());

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('${DateFormat('EEE dd MMM yyyy').format(DateTime.parse('${d['log_date']}'))}  ·  submitted by ${d['submitted_by_name'] ?? '?'} $when',
            style: const TextStyle(color: AppColors.textMuted)),
        const SizedBox(height: 4),
        Text('${points.length} of ${(d['data_points'] as List).length} values filled',
            style: const TextStyle(color: AppColors.textMuted)),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: Column(
              children: [
                for (final p in points) _valueRow(p as Map, readings[p['id']] as Map),
              ],
            ),
          ),
        ),
        if (photos.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Text('Photos', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [for (final p in photos) _photo(p)],
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _valueRow(Map p, Map r) {
    final value = '${r['value']}';
    final unit = (p['unit'] ?? '') as String;
    final n = double.tryParse(value);
    final min = (p['min'] as num?)?.toDouble();
    final max = (p['max'] as num?)?.toDouble();
    final out = n != null && ((min != null && n < min) || (max != null && n > max));
    final reader = r['ocr_value'];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.textFaint.withValues(alpha: 0.15)))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${p['name']}'),
                if (min != null || max != null)
                  Text('normal ${min ?? '…'} – ${max ?? '…'} $unit', style: const TextStyle(color: AppColors.textFaint, fontSize: 11.5)),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('$value $unit'.trim(),
                    style: TextStyle(fontWeight: FontWeight.w700, color: out ? AppColors.alarm : AppColors.textPrimary)),
                if (reader != null && '$reader' != value)
                  Text('reader read $reader', style: const TextStyle(color: AppColors.gold, fontSize: 11.5)),
                if (out) const Text('outside the normal range', style: TextStyle(color: AppColors.alarm, fontSize: 11.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _photo(Map p) {
    if (p['received'] != 1 && p['received'] != true) {
      // photos go up only when the crew taps Upload photos on the tablet (large data, sent later)
      return _tile(const Padding(
        padding: EdgeInsets.all(8),
        child: Text('Photo not uploaded yet\n(still on the tablet)', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
      ));
    }
    if (p['mime'] == 'application/pdf') {
      return _tile(const Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.picture_as_pdf, size: 36), Text('PDF')]));
    }
    return FutureBuilder<Uint8List>(
      future: _signing.photo('${p['id']}'),
      builder: (context, snap) => snap.hasData
          ? GestureDetector(
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => Dialog(child: InteractiveViewer(maxScale: 6, child: Image.memory(snap.data!))),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(snap.data!, width: 160, height: 120, fit: BoxFit.cover),
              ),
            )
          : _tile(snap.hasError
              ? const Icon(Icons.broken_image_outlined)
              : const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
    );
  }

  Widget _tile(Widget child) => Container(
        width: 160,
        height: 120,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppColors.ink900.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(10)),
        child: child,
      );
}
