import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/logbook_entry.dart';
import '../providers/history_provider.dart';
import '../theme/app_colors.dart';

enum _Compute { direct, max, min, combine }

/// One row of the curated daily-log report — mirrors the paper "Diesel
/// Alternator" log sheet exactly (Power, Current, Exh Gas Max/Min, ...).
/// Pulls from whichever parameter keys actually hold that data — some rows
/// come from the remote panel, some from local, some (like cylinder
/// max/min) are computed across several keys instead of being one direct
/// reading.
class _LogRow {
  final String label;
  final String unit;
  final _Compute compute;
  final List<String> keys;
  final double factor;

  const _LogRow({required this.label, required this.unit, required this.compute, required this.keys, this.factor = 1});
}

const _dailyLogRows = <_LogRow>[
  _LogRow(label: 'Power', unit: 'Kw.', compute: _Compute.direct, keys: ['load_kw']),
  _LogRow(label: 'Current', unit: 'Amps.', compute: _Compute.direct, keys: ['loc_current_amps']),
  _LogRow(
    label: 'Exh. Gas Out.T. Max./Cyl.',
    unit: '°C',
    compute: _Compute.max,
    keys: ['exh_temp_cyl1', 'exh_temp_cyl2', 'exh_temp_cyl3', 'exh_temp_cyl4', 'exh_temp_cyl5', 'exh_temp_cyl6'],
  ),
  _LogRow(
    label: 'Exh. Gas Out.T. Min./Cyl.',
    unit: '°C',
    compute: _Compute.min,
    keys: ['exh_temp_cyl1', 'exh_temp_cyl2', 'exh_temp_cyl3', 'exh_temp_cyl4', 'exh_temp_cyl5', 'exh_temp_cyl6'],
  ),
  _LogRow(
    label: 'J.C.W. Out. Max./Cyl.',
    unit: '°C',
    compute: _Compute.max,
    keys: ['loc_jcw_out_u1', 'loc_jcw_out_u2', 'loc_jcw_out_u3', 'loc_jcw_out_u4', 'loc_jcw_out_u5', 'loc_jcw_out_u6'],
  ),
  _LogRow(
    label: 'J.C.W. Out. Min./Cyl.',
    unit: '°C',
    compute: _Compute.min,
    keys: ['loc_jcw_out_u1', 'loc_jcw_out_u2', 'loc_jcw_out_u3', 'loc_jcw_out_u4', 'loc_jcw_out_u5', 'loc_jcw_out_u6'],
  ),
  _LogRow(label: 'Scavenge Air T', unit: '°C', compute: _Compute.direct, keys: ['loc_charge_air_clr_inlet_temp']),
  _LogRow(label: 'Lub.Oil P.', unit: 'bar', compute: _Compute.direct, keys: ['lo_press'], factor: 10),
  _LogRow(label: 'Lub.Oil T.', unit: '°C', compute: _Compute.direct, keys: ['lo_temp']),
  _LogRow(label: 'Fuel Oil P.', unit: 'bar', compute: _Compute.direct, keys: ['fo_press'], factor: 10),
  _LogRow(label: 'Fuel Oil T./Visco.', unit: '°C/cSt.', compute: _Compute.combine, keys: ['fo_temp', 'loc_fo_viscosity']),
  _LogRow(label: 'Fwd./Aft. Ped. Brg. T.', unit: '°C', compute: _Compute.direct, keys: ['loc_ped_brg_temp']),
  _LogRow(label: 'Sump', unit: '%', compute: _Compute.direct, keys: ['loc_sump_pct']),
  _LogRow(label: 'Running Hours', unit: 'hrs', compute: _Compute.direct, keys: ['loc_running_hours']),
];

/// One Time or Noon reading slot for one calendar day.
class _LogColumn {
  final DateTime date;
  final String slotLabel; // 'Time' or 'Noon'
  final LogbookEntry? entry;
  _LogColumn({required this.date, required this.slotLabel, required this.entry});
}

/// The "daily log sheet" view — parameters down the rows, Time/Noon columns
/// across, same shape as the paper log tables. Built entirely from what's
/// already been entered on the form (both remote and local); nothing new
/// is typed here. Values that don't map to one direct field (cylinder
/// max/min, combined fuel temp+viscosity) are computed from the underlying
/// readings instead.
class DailyLogTable extends ConsumerWidget {
  final int generatorNumber;
  const DailyLogTable({super.key, required this.generatorNumber});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(recentEntriesProvider);

    return entriesAsync.when(
      loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
      error: (e, st) => Padding(padding: const EdgeInsets.all(20), child: Text('Error: $e')),
      data: (allEntries) {
        final entries = allEntries.where((e) => (e.generatorNumber ?? 1) == generatorNumber).toList();
        if (entries.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Text('No readings logged yet — submit an entry to see it here.', style: TextStyle(color: AppColors.textMuted)),
          );
        }

        final columns = _buildColumns(entries);
        final dateFormat = DateFormat('dd MMM');

        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AUXILIARY ENGINE — DAILY LOG',
                  style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 0.6),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowHeight: 50,
                    dataRowMinHeight: 40,
                    dataRowMaxHeight: 40,
                    columnSpacing: 18,
                    headingTextStyle: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700, fontSize: 11),
                    dataTextStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 12.5),
                    columns: [
                      const DataColumn(label: Text('Parameter')),
                      for (final c in columns)
                        DataColumn(label: Text('${dateFormat.format(c.date)}\n${c.slotLabel}')),
                    ],
                    rows: [
                      for (final row in _dailyLogRows)
                        DataRow(cells: [
                          DataCell(Text('${row.label} ${row.unit}', style: const TextStyle(fontWeight: FontWeight.w600))),
                          for (final c in columns) DataCell(Text(_valueFor(row, c.entry))),
                        ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// One column per Time/Noon slot per calendar day, oldest day first.
  /// "Noon" is whichever entry falls between 11:00–13:00; "Time" is the
  /// earliest other reading that day — matching the paper sheet's fixed
  /// two-reading-a-day layout.
  List<_LogColumn> _buildColumns(List<LogbookEntry> entries) {
    final byDate = <DateTime, List<LogbookEntry>>{};
    for (final e in entries) {
      final day = DateTime(e.timestamp.year, e.timestamp.month, e.timestamp.day);
      byDate.putIfAbsent(day, () => []).add(e);
    }

    final days = byDate.keys.toList()..sort();
    final columns = <_LogColumn>[];
    for (final day in days) {
      final dayEntries = byDate[day]!..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      LogbookEntry? noon;
      LogbookEntry? time;
      for (final e in dayEntries) {
        if (_slotFor(e) == 'noon') {
          noon ??= e;
        } else {
          time ??= e;
        }
      }
      columns.add(_LogColumn(date: day, slotLabel: 'Time', entry: time));
      columns.add(_LogColumn(date: day, slotLabel: 'Noon', entry: noon));
    }
    return columns;
  }

  /// The entry's explicitly chosen Time/Noon column, or — for legacy
  /// entries saved before that selector existed — a guess from the hour.
  String _slotFor(LogbookEntry e) {
    if (e.readingSlot == 'time' || e.readingSlot == 'noon') return e.readingSlot!;
    final hour = e.timestamp.hour;
    return (hour >= 11 && hour < 13) ? 'noon' : 'time';
  }

  String _valueFor(_LogRow row, LogbookEntry? entry) {
    if (entry == null) return '—';
    final values = entry.paramValues;

    switch (row.compute) {
      case _Compute.direct:
        final raw = values[row.keys.first];
        return _formatNumber(raw, row.factor);
      case _Compute.max:
      case _Compute.min:
        final nums = row.keys.map((k) => double.tryParse(values[k] ?? '')).whereType<double>().toList();
        if (nums.isEmpty) return '—';
        final result = row.compute == _Compute.max
            ? nums.reduce((a, b) => a > b ? a : b)
            : nums.reduce((a, b) => a < b ? a : b);
        return _trim(result);
      case _Compute.combine:
        final a = values[row.keys[0]];
        final b = values[row.keys[1]];
        if ((a == null || a.isEmpty) && (b == null || b.isEmpty)) return '—';
        return '${a?.isNotEmpty == true ? a : '—'} / ${b?.isNotEmpty == true ? b : '—'}';
    }
  }

  String _formatNumber(String? raw, double factor) {
    if (raw == null || raw.isEmpty) return '—';
    final n = double.tryParse(raw);
    if (n == null) return raw;
    return _trim(n * factor);
  }

  String _trim(double n) {
    final rounded = (n * 10).round() / 10;
    return rounded == rounded.roundToDouble() ? rounded.toStringAsFixed(0) : rounded.toString();
  }
}
