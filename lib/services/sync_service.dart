import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../data/app_database.dart';
import '../data/logbook_repository.dart';
import '../models/logbook_entry.dart';
import '../providers/session_provider.dart';
import 'auth_service.dart';
import 'server_config.dart';

class RefusedChange {
  final DateTime at;
  final String type;
  final String? logId;
  final String message;
  const RefusedChange(this.at, this.type, this.logId, this.message);
}

class SyncState {
  final bool running;
  final DateTime? lastOk;
  final String? lastError;
  final bool offline;

  /// The session's token is no longer accepted: sign in again with a connection.
  final bool needsSignIn;
  final int pendingOps;
  final int pendingPhotos;
  final int pendingBytes;
  final List<RefusedChange> refused;

  const SyncState({
    this.running = false,
    this.lastOk,
    this.lastError,
    this.offline = false,
    this.needsSignIn = false,
    this.pendingOps = 0,
    this.pendingPhotos = 0,
    this.pendingBytes = 0,
    this.refused = const [],
  });

  SyncState copyWith({
    bool? running,
    DateTime? lastOk,
    String? lastError,
    bool clearError = false,
    bool? offline,
    bool? needsSignIn,
    int? pendingOps,
    int? pendingPhotos,
    int? pendingBytes,
    List<RefusedChange>? refused,
  }) =>
      SyncState(
        running: running ?? this.running,
        lastOk: lastOk ?? this.lastOk,
        lastError: clearError ? null : (lastError ?? this.lastError),
        offline: offline ?? this.offline,
        needsSignIn: needsSignIn ?? this.needsSignIn,
        pendingOps: pendingOps ?? this.pendingOps,
        pendingPhotos: pendingPhotos ?? this.pendingPhotos,
        pendingBytes: pendingBytes ?? this.pendingBytes,
        refused: refused ?? this.refused,
      );

  /// Days since the last good sync: a banner after 2, an alarm after 7 (design, section 6).
  int? get daysSinceSync => lastOk == null ? null : DateTime.now().difference(lastOk!).inHours ~/ 24;
}

/// Sync with the LogBridge server (design, section 6). Values travel first (small), photos
/// follow (large); every operation carries its own id, the server remembers its answer to
/// each, and a photo counts only when its SHA-256 matches - so every step can be repeated
/// safely. Runs every 45 seconds while the app is open, when it comes back to the front, and
/// on "Sync now"; with the app closed nothing syncs.
class SyncService extends StateNotifier<SyncState> {
  final Ref ref;
  final LogbookRepository repo;
  final Dio Function(String baseUrl, String token) clientFor;

  SyncService(this.ref, {LogbookRepository? repo, Dio Function(String, String)? clientFor})
      : repo = repo ?? LogbookRepository(),
        clientFor = clientFor ?? _client,
        super(const SyncState()) {
    _load();
  }

  static const _prefsLastOk = 'sync_last_ok';
  static const batch = 100;

  static Dio _client(String baseUrl, String token) => Dio(BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 120),
        headers: {'authorization': 'Bearer $token'},
      ));

  Future<void> _load() async {
    try {
      final ms = (await SharedPreferences.getInstance()).getInt(_prefsLastOk);
      if (ms != null) state = state.copyWith(lastOk: DateTime.fromMillisecondsSinceEpoch(ms));
      await refreshCounts();
    } catch (_) {/* no storage (tests): counts stay zero */}
  }

  static String newId() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  static String? mimeOf(String path) => switch (path.split('.').last.toLowerCase()) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        'pdf' => 'application/pdf',
        _ => null,
      };

  /// The operations that put [entry] on the server as its log, submitted for signing:
  /// the log, every value (checked, with what the reader suggested), every photo's details,
  /// then the submit. They wait in the outbox until the server has them.
  ///
  /// [previous]: the same log before it was corrected (sent back): values cleared since are
  /// sent as empty, and photos the server already has are not sent again.
  Future<void> queueSubmit(LogbookEntry entry, ServerConfig cfg, {LogbookEntry? previous}) async {
    final gen = cfg.generators[entry.generatorNumber ?? 1]!;
    final logId = entry.logId!;
    final now = DateTime.now().toUtc().toIso8601String();
    final date = entry.logId!.split('-').skip(3).take(3).join('-');
    final ops = <Map<String, dynamic>>[
      {
        'type': 'log.upsert',
        'id': logId,
        'screen_id': gen.screenId,
        'log_date': date,
        'round': ServerConfig.roundOf(entry.readingSlot ?? 'time'),
        'created_at': entry.timestamp.toUtc().toIso8601String(),
      },
      for (final e in entry.paramValues.entries)
        if (e.value.trim().isNotEmpty && gen.dataPoints.containsKey(e.key))
          {
            'type': 'reading.set',
            'log_id': logId,
            'data_point_id': gen.dataPoints[e.key],
            'value': e.value.trim(),
            'ocr_value': entry.ocrValues[e.key],
            'confirmed': true,
            'flags': <String>[],
            'at': now,
          },
      for (final k in previous?.paramValues.keys ?? const <String>[])
        if ((entry.paramValues[k] ?? '').trim().isEmpty && gen.dataPoints.containsKey(k))
          {'type': 'reading.set', 'log_id': logId, 'data_point_id': gen.dataPoints[k], 'value': null, 'confirmed': true, 'at': now},
    ];
    final db = await AppDatabase.instance.database;
    final alreadySent = {
      for (final r in await db.query('sync_photos', columns: ['path'], where: 'entry_id = ? AND rejected IS NULL', whereArgs: [entry.id]))
        r['path'] as String,
    };

    // every picture of the entry: HMI screen, gauge photos, the whole-entry photo and PDF
    final files = <String>{
      if (entry.hmiPhotoPath != null) entry.hmiPhotoPath!,
      ...entry.paramPhotos.values,
      if (entry.photoPath != null) entry.photoPath!,
      if (entry.pdfPath != null) entry.pdfPath!,
    };
    final photos = <Map<String, Object?>>[];
    for (final path in files.difference(alreadySent)) {
      final mime = mimeOf(path);
      final f = File(path);
      if (mime == null || !await f.exists()) continue;
      final bytes = await f.readAsBytes();
      final sha = await compute((List<int> b) => sha256.convert(b).toString(), bytes);
      final id = newId();
      final takenAt = (await f.lastModified()).toUtc().toIso8601String();
      photos.add({
        'id': id, 'entry_id': entry.id, 'log_id': logId, 'path': path, 'mime': mime,
        'size': bytes.length, 'sha256': sha, 'taken_at': takenAt,
      });
      ops.add({
        'type': 'photo.meta', 'id': id, 'log_id': logId, 'sha256': sha, 'mime': mime, 'size': bytes.length,
        'taken_at': takenAt, 'pos_source': 'none', 'tz_offset_min': DateTime.now().timeZoneOffset.inMinutes,
      });
    }
    ops.add({'type': 'log.submit', 'log_id': logId, 'at': now});

    await db.transaction((txn) async {
      for (final p in photos) {
        await txn.insert('sync_photos', p, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final op in ops) {
        final id = newId();
        await txn.insert('outbox', {
          'op_id': id,
          'type': op['type'],
          'log_id': op['log_id'] ?? op['id'],
          'op': jsonEncode({'op_id': id, ...op}),
          'created_at': now,
        });
      }
    });
    await refreshCounts();
  }

  Future<void> refreshCounts() async {
    final db = await AppDatabase.instance.database;
    final ops = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM outbox')) ?? 0;
    final p = await db.rawQuery('SELECT COUNT(*) n, COALESCE(SUM(size),0) b FROM sync_photos WHERE uploaded = 0 AND rejected IS NULL');
    final refused = await db.query('sync_refused', orderBy: 'id DESC', limit: 50);
    state = state.copyWith(
      pendingOps: ops,
      pendingPhotos: (p.first['n'] as int?) ?? 0,
      pendingBytes: (p.first['b'] as int?) ?? 0,
      refused: [
        for (final r in refused)
          RefusedChange(DateTime.parse(r['at'] as String), r['type'] as String, r['log_id'] as String?, r['message'] as String),
      ],
    );
  }

  /// The refused list has been read: clear it (and let refused photos go from the queue).
  Future<void> clearRefused() async {
    final db = await AppDatabase.instance.database;
    await db.delete('sync_refused');
    await db.delete('sync_photos', where: 'rejected IS NOT NULL');
    await refreshCounts();
  }

  static bool _unreachable(DioException e) => e.response == null;

  Future<void> syncNow({bool manual = false}) async {
    final session = ref.read(sessionProvider);
    if (state.running || session == null || !session.user.canCapture) return;
    state = state.copyWith(running: true, clearError: true);
    final dio = clientFor(session.serverUrl, session.token);
    try {
      await _pushValues(dio);
      await _pushPhotos(dio);
      await _pull(dio);
      // the vessel configuration may have changed (e.g. a generator added on the server)
      final cfg = (await dio.get('/api/config')).data;
      if (cfg is Map<String, dynamic>) await ref.read(authServiceProvider).storeConfig(session.user.username, cfg);
      final now = DateTime.now();
      await (await SharedPreferences.getInstance()).setInt(_prefsLastOk, now.millisecondsSinceEpoch);
      state = state.copyWith(lastOk: now, offline: false, needsSignIn: false);
      if (session.offline) {
        // the server answered: this session is online now
        ref.read(sessionProvider.notifier).state =
            Session(user: session.user, token: session.token, offline: false, serverUrl: session.serverUrl);
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        state = state.copyWith(needsSignIn: true, lastError: 'The server no longer accepts this sign-in. Sign out and sign in again with a connection.');
      } else if (_unreachable(e)) {
        state = state.copyWith(offline: true, lastError: manual ? 'No connection to the server right now' : null, clearError: !manual);
      } else {
        state = state.copyWith(lastError: 'The server answered ${e.response?.statusCode}');
      }
    } catch (e) {
      state = state.copyWith(lastError: '$e');
    } finally {
      state = state.copyWith(running: false);
      try {
        await refreshCounts();
      } catch (_) {/* storage unreadable: the counts stay as they were */}
    }
  }

  Future<void> _pushValues(Dio dio) async {
    final db = await AppDatabase.instance.database;
    for (;;) {
      final rows = await db.query('outbox', orderBy: 'seq', limit: batch);
      if (rows.isEmpty) return;
      final ops = [for (final r in rows) jsonDecode(r['op'] as String)];
      final res = await dio.post('/api/sync/values', data: {'ops': ops});
      final results = ((res.data as Map)['results'] as List).cast<Map>();
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        final r = i < results.length ? results[i] : const {};
        final type = row['type'] as String;
        final logId = row['log_id'] as String?;
        if (r['status'] == 'ok') {
          final op = jsonDecode(row['op'] as String) as Map;
          if (type == 'photo.meta') await db.update('sync_photos', {'meta_synced': 1}, where: 'id = ?', whereArgs: [op['id']]);
          if (type == 'log.submit' && logId != null) await repo.setStatus(logId, 'submitted');
          // the log already exists on the server and is no longer open there
          if (type == 'log.upsert' && logId != null && const {'submitted', 'approved'}.contains(r['log_status'])) {
            await repo.setStatus(logId, '${r['log_status']}');
          }
        } else {
          // the server's "no" is final (it remembers it), so record it and move on
          final msg = '${r['message'] ?? 'Not accepted'}';
          await db.insert('sync_refused', {'at': DateTime.now().toIso8601String(), 'type': type, 'log_id': logId, 'message': msg});
          if (type == 'log.submit' && logId != null && await repo.statusOf(logId) == 'submitted') {
            await repo.setStatus(logId, 'draft', reason: msg);
          }
          if (type == 'photo.meta') {
            final op = jsonDecode(row['op'] as String) as Map;
            await db.update('sync_photos', {'rejected': msg}, where: 'id = ?', whereArgs: [op['id']]);
          }
        }
        await db.delete('outbox', where: 'seq = ?', whereArgs: [row['seq']]);
      }
    }
  }

  Future<void> _pushPhotos(Dio dio) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('sync_photos', where: 'meta_synced = 1 AND uploaded = 0 AND rejected IS NULL');
    for (final p in rows) {
      final f = File(p['path'] as String);
      if (!await f.exists()) {
        await db.update('sync_photos', {'rejected': 'The file is no longer on this tablet'}, where: 'id = ?', whereArgs: [p['id']]);
        continue;
      }
      try {
        final res = await dio.put('/api/sync/photos/${p['id']}',
            data: Stream.fromIterable([await f.readAsBytes()]),
            options: Options(headers: {'content-type': p['mime'], Headers.contentLengthHeader: p['size']}));
        final d = res.data as Map;
        // confirmed: the server holds the same bytes
        if (d['received'] == true && d['sha256'] == p['sha256']) {
          await db.update('sync_photos', {'uploaded': 1}, where: 'id = ?', whereArgs: [p['id']]);
        }
      } on DioException catch (e) {
        if (_unreachable(e) || e.response?.statusCode == 401) rethrow;
        final msg = (e.response?.data is Map ? e.response!.data['error'] : null) ?? 'The server refused this photo';
        await db.update('sync_photos', {'rejected': '$msg'}, where: 'id = ?', whereArgs: [p['id']]);
      }
    }
  }

  /// The server's status wins once this tablet's own changes for a log have gone up:
  /// submitted, signed, or sent back with a reason.
  Future<void> _pull(Dio dio) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      "SELECT DISTINCT log_id FROM logbook_entries WHERE log_id IS NOT NULL AND status IN ('submitted', 'rejected', 'draft') "
      'AND log_id NOT IN (SELECT log_id FROM outbox WHERE log_id IS NOT NULL)',
    );
    for (final r in rows) {
      final logId = r['log_id'] as String;
      try {
        final d = (await dio.get('/api/logs/${Uri.encodeComponent(logId)}')).data as Map;
        final status = '${d['status']}';
        final local = await repo.statusOf(logId);
        if (local == 'draft' && status == 'draft') continue; // refused locally; keep the reason
        if (status != local) await repo.setStatus(logId, status, reason: d['reject_reason'] as String?);
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) continue; // not on the server (yet)
        rethrow;
      }
    }
  }

  /// Bytes the app's own files take on this tablet (photos, PDFs, the database).
  static Future<int> storageUsed() async {
    var total = 0;
    try {
      final dir = await getApplicationDocumentsDirectory();
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File) total += await e.length();
      }
    } catch (_) {}
    return total;
  }
}

final syncProvider = StateNotifierProvider<SyncService, SyncState>((ref) => SyncService(ref));
