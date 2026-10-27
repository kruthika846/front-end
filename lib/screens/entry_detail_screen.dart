import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/logbook_entry.dart';
import '../models/param_definition.dart';
import '../providers/repository_providers.dart';
import '../theme/app_colors.dart';
import '../widgets/log_status_chip.dart';

/// Read-only summary of one saved entry. Pulls the same parameter config
/// (labels, units, groups) the entry form used, so a saved reading shows
/// "JCW Outlet Temp — 45 °C" instead of the raw storage key "loc_jcw_out_u1".
/// Editing readings and per-panel comments happens on the entry form itself,
/// before the signature locks the record in — not here.
class EntryDetailScreen extends ConsumerWidget {
  final LogbookEntry entry;
  const EntryDetailScreen({super.key, required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(parameterConfigProvider);
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');

    return Scaffold(
      appBar: AppBar(title: Text('Entry — ${dateFormat.format(entry.timestamp)}')),
      body: configAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Failed to load parameter labels: $e')),
        data: (config) {
          final remoteGroups = _groupFilled(config.remoteParams, entry.paramValues);
          final localGroups = _groupFilled(config.localParams, entry.paramValues);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(entry.engineId, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(dateFormat.format(entry.timestamp), style: const TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [LogStatusChip(entry: entry), _VerificationBadge(entry: entry)],
              ),
              if (entry.rejectReason != null && (entry.status == 'rejected' || entry.status == 'draft')) ...[
                const SizedBox(height: 8),
                Text(entry.rejectReason!, style: const TextStyle(color: AppColors.alarm)),
              ],
              const SizedBox(height: 20),
              if (remoteGroups.isNotEmpty) ...[
                const _SectionTitle(icon: Icons.satellite_alt, text: 'Remote Parameters', color: AppColors.cyan),
                const SizedBox(height: 10),
                for (final g in remoteGroups.entries)
                  _ParamGroupTable(
                    title: g.key,
                    params: g.value,
                    values: entry.paramValues,
                    comment: entry.groupComments['remote::${g.key}'],
                  ),
              ],
              if (localGroups.isNotEmpty) ...[
                const SizedBox(height: 8),
                const _SectionTitle(icon: Icons.build_circle_outlined, text: 'Local Parameters', color: AppColors.teal),
                const SizedBox(height: 10),
                for (final g in localGroups.entries)
                  _ParamGroupTable(
                    title: g.key,
                    params: g.value,
                    values: entry.paramValues,
                    comment: entry.groupComments['local::${g.key}'],
                  ),
              ],
              if (entry.notes != null && entry.notes!.isNotEmpty) ...[
                const SizedBox(height: 8),
                const _SectionTitle(icon: Icons.notes, text: 'Notes', color: AppColors.gold),
                const SizedBox(height: 10),
                Card(child: Padding(padding: const EdgeInsets.all(14), child: Text(entry.notes!))),
              ],
              if (entry.hmiPhotoPath != null) ...[
                const SizedBox(height: 20),
                Text('HMI Screen Photo', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(File(entry.hmiPhotoPath!), height: 180, width: double.infinity, fit: BoxFit.cover),
                ),
              ],
              if (entry.photoPath != null) ...[
                const SizedBox(height: 20),
                Text('Photo', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(File(entry.photoPath!), height: 180, width: double.infinity, fit: BoxFit.cover),
                ),
              ],
              if (entry.signaturePath != null) ...[
                const SizedBox(height: 20),
                Text('Signature', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Container(
                  height: 120,
                  width: double.infinity,
                  decoration: BoxDecoration(border: Border.all(color: AppColors.textFaint), borderRadius: BorderRadius.circular(8)),
                  child: Image.file(File(entry.signaturePath!)),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Groups only the parameters that actually have a recorded value for
  /// this entry, preserving the schema's declared order within each group.
  Map<String, List<ParamDefinition>> _groupFilled(List<ParamDefinition> defs, Map<String, String> values) {
    final result = <String, List<ParamDefinition>>{};
    for (final p in defs) {
      if (values.containsKey(p.key)) {
        result.putIfAbsent(p.group ?? 'Other', () => []).add(p);
      }
    }
    return result;
  }
}

/// Proof of who submitted this entry and how — a real biometric check
/// (current entries) or, for entries saved before that existed, the old
/// drawn signature further down the page. Never both are "unverified" for
/// a legitimately-submitted entry, so this always has something to show.
class _VerificationBadge extends StatelessWidget {
  final LogbookEntry entry;
  const _VerificationBadge({required this.entry});

  @override
  Widget build(BuildContext context) {
    if (entry.biometricVerified) {
      return _badge(
        icon: Icons.verified_user,
        color: AppColors.good,
        text: 'Biometrically verified — ${entry.operatorName ?? 'operator'}',
      );
    }
    if (entry.signaturePath != null) {
      return _badge(
        icon: Icons.draw_outlined,
        color: AppColors.textMuted,
        text: 'Signed (legacy entry — see signature below)',
      );
    }
    // a server log: the person who captured it is recorded there; the PIN signature comes from the signer
    if (entry.status != 'local' && entry.operatorName != null) {
      return _badge(icon: Icons.person_outline, color: AppColors.textMuted, text: 'Captured by ${entry.operatorName}');
    }
    return _badge(icon: Icons.help_outline, color: AppColors.alarm, text: 'No verification on record');
  }

  Widget _badge({required IconData icon, required Color color, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _SectionTitle({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

/// A labeled group of parameters rendered as a real two-column table —
/// Parameter on the left, Value (with its unit) right-aligned on the right
/// — instead of a flat unordered list, so scanning a saved entry reads the
/// way a log sheet does. Shows the panel's comment (entered on the form),
/// if there is one, read-only underneath.
class _ParamGroupTable extends StatelessWidget {
  final String title;
  final List<ParamDefinition> params;
  final Map<String, String> values;
  final String? comment;

  const _ParamGroupTable({required this.title, required this.params, required this.values, this.comment});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.toUpperCase(),
                style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 0.6),
              ),
              const SizedBox(height: 4),
              Table(
                columnWidths: const {0: FlexColumnWidth(3), 1: FlexColumnWidth(2)},
                children: [
                  for (final p in params)
                    TableRow(
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.textFaint.withValues(alpha: 0.15)))),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Text(p.label, style: const TextStyle(color: AppColors.textPrimary)),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Text(
                            _formatValue(p),
                            textAlign: TextAlign.right,
                            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              if (comment != null && comment!.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.ink900.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(comment!, style: const TextStyle(color: AppColors.textMuted, fontSize: 13, fontStyle: FontStyle.italic)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatValue(ParamDefinition p) {
    final raw = values[p.key] ?? '';
    if (raw.isEmpty) return '—';
    return p.unit.isEmpty ? raw : '$raw ${p.unit}';
  }
}
