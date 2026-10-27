import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/logbook_entry.dart';
import '../providers/history_provider.dart';
import '../theme/app_colors.dart';
import 'delete_entry_action.dart';

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

  /// For max/min rows only — a short name per entry in [keys] (e.g. "Cyl 1",
  /// "Unit 3"), shown in brackets next to the value so it's clear which
  /// cylinder/unit actually produced that max or min reading.
  final List<String>? keyLabels;

  const _LogRow({
    required this.label,
    required this.unit,
    required this.compute,
    required this.keys,
    this.factor = 1,
    this.keyLabels,
  });
}

const _dailyLogRows = <_LogRow>[
  _LogRow(label: 'Power', unit: 'Kw.', compute: _Compute.direct, keys: ['load_kw']),
  _LogRow(label: 'Current', unit: 'Amps.', compute: _Compute.direct, keys: ['loc_current_amps']),
  _LogRow(
    label: 'Exh. Gas Out.T. Max./Cyl.',
    unit: '°C',
    compute: _Compute.max,
    keys: ['exh_temp_cyl1', 'exh_temp_cyl2', 'exh_temp_cyl3', 'exh_temp_cyl4', 'exh_temp_cyl5', 'exh_temp_cyl6'],
    keyLabels: ['Cyl 1', 'Cyl 2', 'Cyl 3', 'Cyl 4', 'Cyl 5', 'Cyl 6'],
  ),
  _LogRow(
    label: 'Exh. Gas Out.T. Min./Cyl.',
    unit: '°C',
    compute: _Compute.min,
    keys: ['exh_temp_cyl1', 'exh_temp_cyl2', 'exh_temp_cyl3', 'exh_temp_cyl4', 'exh_temp_cyl5', 'exh_temp_cyl6'],
    keyLabels: ['Cyl 1', 'Cyl 2', 'Cyl 3', 'Cyl 4', 'Cyl 5', 'Cyl 6'],
  ),
  _LogRow(
    label: 'J.C.W. Out. Max./Cyl.',
    unit: '°C',
    compute: _Compute.max,
    keys: ['loc_jcw_out_u1', 'loc_jcw_out_u2', 'loc_jcw_out_u3', 'loc_jcw_out_u4', 'loc_jcw_out_u5', 'loc_jcw_out_u6'],
    keyLabels: ['Unit 1', 'Unit 2', 'Unit 3', 'Unit 4', 'Unit 5', 'Unit 6'],
  ),
  _LogRow(
    label: 'J.C.W. Out. Min./Cyl.',
    unit: '°C',
    compute: _Compute.min,
    keys: ['loc_jcw_out_u1', 'loc_jcw_out_u2', 'loc_jcw_out_u3', 'loc_jcw_out_u4', 'loc_jcw_out_u5', 'loc_jcw_out_u6'],
    keyLabels: ['Unit 1', 'Unit 2', 'Unit 3', 'Unit 4', 'Unit 5', 'Unit 6'],
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
class DailyLogTable extends ConsumerStatefulWidget {
  final int generatorNumber;

  /// Logs to show instead of this tablet's own entries (the Log book tab passes the server's).
  final List<LogbookEntry>? entries;

  /// No delete buttons: the Log book shows server logs, which are not deleted from a tablet.
  final bool readOnly;

  const DailyLogTable({super.key, required this.generatorNumber, this.entries, this.readOnly = false});

  @override
  ConsumerState<DailyLogTable> createState() => _DailyLogTableState();
}

class _DailyLogTableState extends ConsumerState<DailyLogTable> {
  final _scrollController = ScrollController();
  int _lastColumnCount = 0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// The table is oldest-day-first, matching the paper log's reading order —
  /// but that means a just-submitted entry lands off-screen to the right,
  /// with no visual hint there's more to scroll to. Whenever a new column
  /// shows up (a new day, or filling in today's other slot), jump the view
  /// to the end so the newest reading is immediately visible. Doesn't fire
  /// on every rebuild — only when the column count actually grows — so it
  /// never fights someone who's manually scrolled back to review history.
  void _scrollToEndIfNewColumn(int columnCount) {
    if (columnCount <= _lastColumnCount) return;
    _lastColumnCount = columnCount;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final entriesAsync = widget.entries != null
        ? AsyncValue<List<LogbookEntry>>.data(widget.entries!)
        : ref.watch(recentEntriesProvider(widget.generatorNumber));

    return entriesAsync.when(
      loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
      error: (e, st) => Padding(padding: const EdgeInsets.all(20), child: Text('Error: $e')),
      data: (allEntries) {
        final entries = allEntries.where((e) => (e.generatorNumber ?? 1) == widget.generatorNumber).toList();
        if (entries.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Text('No readings logged yet — submit an entry to see it here.', style: TextStyle(color: AppColors.textMuted)),
          );
        }

        final columns = _buildColumns(entries);
        _scrollToEndIfNewColumn(columns.length);
        final dateFormat = DateFormat('dd MMM');
        final timeFormat = DateFormat('HH:mm');

        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'AUXILIARY ENGINE — DAILY LOG',
                        style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 0.6),
                      ),
                    ),
                    if (columns.length > 2) ...[
                      const Icon(Icons.swipe, size: 13, color: AppColors.textFaint),
                      const SizedBox(width: 4),
                      const Text('scroll for more days', style: TextStyle(color: AppColors.textFaint, fontSize: 10)),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                ..._remarksSection(columns, dateFormat, timeFormat),
                Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(bottom: 12),
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
                          DataColumn(
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('${dateFormat.format(c.date)}\n${_headerSecondLine(c, timeFormat)}'),
                                if (c.entry != null && !widget.readOnly) ...[
                                  const SizedBox(width: 2),
                                  InkWell(
                                    borderRadius: BorderRadius.circular(999),
                                    onTap: () => confirmAndDeleteEntry(context, ref, c.entry!),
                                    child: const Padding(
                                      padding: EdgeInsets.all(4),
                                      child: Icon(Icons.delete_outline, size: 15, color: AppColors.alarm),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
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
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// A real paper log always ends in a Remarks line — but a comment here
  /// usually exists to explain an abnormal/out-of-range reading, which is
  /// exactly the kind of thing that shouldn't wait to be noticed at the
  /// bottom of the panel. Shown in full (no truncation, no tapping for the
  /// rest) right at the top, but as a compact flagged banner rather than a
  /// wall of bold text — still impossible to miss, without dominating the
  /// panel.
  List<Widget> _remarksSection(List<_LogColumn> columns, DateFormat dateFormat, DateFormat timeFormat) {
    final withComments = columns.where((c) => c.entry?.combinedComments.isNotEmpty ?? false).toList();
    if (withComments.isEmpty) return const [];
    return [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: AppColors.alarm.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.alarm.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 13, color: AppColors.alarm),
                SizedBox(width: 4),
                Text(
                  'REMARKS',
                  style: TextStyle(color: AppColors.alarm, fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 0.6),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final c in withComments)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 11, color: AppColors.alarm, height: 1.3),
                    children: [
                      TextSpan(
                        text: '${dateFormat.format(c.date)} ${_headerSecondLine(c, timeFormat)}:  ',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      TextSpan(text: c.entry!.combinedComments),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 10),
    ];
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

  /// Second line of a column header: the actual 24-hour time the entry was
  /// submitted at (not just the static "Time"/"Noon" slot name), so the
  /// sheet shows exactly when each reading was logged — matching the paper
  /// sheet's "date + time" columns. The Noon column keeps its "Noon" label
  /// with the real time appended after a "/"; an empty slot (no entry yet)
  /// just falls back to the plain slot name since there's no time to show.
  String _headerSecondLine(_LogColumn c, DateFormat timeFormat) {
    if (c.entry == null) return c.slotLabel;
    final time = timeFormat.format(c.entry!.timestamp);
    final signed = c.entry!.status == 'approved' ? ' ✓' : ''; // signed and final
    return c.slotLabel == 'Noon' ? 'Noon / $time$signed' : '$time$signed';
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
        // Track which key produced the extreme value, not just the value
        // itself, so the reading can be labelled with its cylinder/unit.
        int? bestIndex;
        double? bestValue;
        for (var i = 0; i < row.keys.length; i++) {
          final n = double.tryParse(values[row.keys[i]] ?? '');
          if (n == null) continue;
          final isBetter = bestValue == null || (row.compute == _Compute.max ? n > bestValue : n < bestValue);
          if (isBetter) {
            bestValue = n;
            bestIndex = i;
          }
        }
        if (bestValue == null) return '—';
        final valueText = _trim(bestValue);
        if (row.keyLabels != null && bestIndex != null && bestIndex < row.keyLabels!.length) {
          return '$valueText (${row.keyLabels![bestIndex]})';
        }
        return valueText;
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
    // double.round() throws outright on Infinity/NaN — and now that a
    // reading is never blocked for being out of range, an operator can
    // type something extreme enough to overflow to Infinity when parsed
    // (or multiplied by a unit-conversion factor). Guard it instead of
    // letting the whole Daily Log crash over one bad cell.
    if (!n.isFinite) return '—';
    final rounded = (n * 10).round() / 10;
    return rounded == rounded.roundToDouble() ? rounded.toStringAsFixed(0) : rounded.toString();
  }
}
