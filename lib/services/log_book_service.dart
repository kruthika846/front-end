import 'package:dio/dio.dart';
import '../data/logbook_repository.dart';
import '../models/logbook_entry.dart';
import 'auth_service.dart';

/// The log book from the LogBridge server (design, section 3): the aux engine log of each of
/// the last days as the server holds it - every generator, Time and Noon, with each log's
/// status. Dashboard viewers get signed logs only (the server decides).
class LogBook {
  /// Generator number -> its logs, as entries for the daily log sheet.
  final Map<int, List<LogbookEntry>> byGenerator;
  final bool fromServer;
  final String? error;
  const LogBook(this.byGenerator, {required this.fromServer, this.error});
}

class LogBookService {
  final Session session;
  final LogbookRepository repo;
  final Dio _dio;

  LogBookService(this.session, {LogbookRepository? repo, Dio? dio})
      : repo = repo ?? LogbookRepository(),
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: session.serverUrl,
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 30),
              headers: {'authorization': 'Bearer ${session.token}'},
            ));

  static const logType = 'aux_engine';
  static const _hourOf = {1: 8, 2: 12}; // a log without a recorded time sits at its round's hour

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<LogBook> load({int days = 7, DateTime? today}) async {
    final end = today ?? DateTime.now();
    final byGenerator = <int, List<LogbookEntry>>{};
    // this tablet's own copies: their real times and panel comments (comments stay on the tablet)
    // (only extras: if the tablet's database can't be read, the server's sheet still shows)
    var local = <String, LogbookEntry>{};
    try {
      local = {for (final e in await repo.fetchRecentEntries(limit: 500)) if (e.logId != null) e.logId!: e};
    } catch (_) {}

    for (var back = days - 1; back >= 0; back--) {
      final date = _day(DateTime(end.year, end.month, end.day - back));
      final sheet = (await _dio.get('/api/daysheet', queryParameters: {'date': date, 'log_type': logType})).data as Map;
      for (final section in (sheet['sections'] as List)) {
        for (final screen in (section['screens'] as List)) {
          final m = RegExp(r'^AE-GEN-(\d+)$').firstMatch('${screen['code']}');
          if (m == null) continue;
          final gen = int.parse(m.group(1)!);
          final statuses = (screen['logs'] as Map).map((k, v) => MapEntry(int.parse('$k'), v as String?));
          for (final entry in statuses.entries) {
            final round = entry.key;
            final status = entry.value;
            if (status == null) continue; // no log for this round
            final values = <String, String>{
              for (final row in (screen['rows'] as List))
                if ((row['cells'] as Map)['$round'] != null) '${row['key']}': '${(row['cells'] as Map)['$round']['v']}',
            };
            final logId = 'L-${session.user.vesselId}-${screen['id']}-$date-$round';
            final mine = local[logId];
            final day = DateTime.parse(date);
            byGenerator.putIfAbsent(gen, () => []).add(LogbookEntry(
                  id: mine?.id ?? logId,
                  engineId: 'Aux Engine $gen',
                  generatorNumber: gen,
                  readingSlot: round == 2 ? 'noon' : 'time',
                  timestamp: mine?.timestamp ?? DateTime(day.year, day.month, day.day, _hourOf[round] ?? 8),
                  operatorName: mine?.operatorName,
                  paramValues: values,
                  groupComments: mine?.groupComments ?? const {},
                  logId: logId,
                  status: status,
                  rejectReason: mine?.rejectReason,
                  synced: true,
                ));
          }
        }
      }
    }
    return LogBook(byGenerator, fromServer: true);
  }
}
