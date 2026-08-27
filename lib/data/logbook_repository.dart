import 'package:sqflite/sqflite.dart';
import '../models/logbook_entry.dart';
import '../models/param_definition.dart';
import 'app_database.dart';

class LogbookRepository {
  Future<void> saveEntry(
    LogbookEntry entry, {
    required Map<String, ParamCategory> categoryByKey,
  }) async {
    final db = await AppDatabase.instance.database;

    await db.transaction((txn) async {
      await txn.insert(
        'logbook_entries',
        {
          'id': entry.id,
          'engine_id': entry.engineId,
          'generator_number': entry.generatorNumber,
          'reading_slot': entry.readingSlot,
          'entry_timestamp': entry.timestamp.toIso8601String(),
          'notes': entry.notes,
          'signature_path': entry.signaturePath,
          'photo_path': entry.photoPath,
          'pdf_path': entry.pdfPath,
          'hmi_photo_path': entry.hmiPhotoPath,
          'synced': entry.synced ? 1 : 0,
          'created_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      for (final e in entry.paramValues.entries) {
        final category = categoryByKey[e.key] ?? ParamCategory.remote;
        await txn.insert('parameter_values', {
          'entry_id': entry.id,
          'param_key': e.key,
          'param_category': category.name,
          'value': e.value,
          'photo_path': entry.paramPhotos[e.key],
        });
      }

      for (final c in entry.groupComments.entries) {
        if (c.value.trim().isEmpty) continue;
        await txn.insert(
          'group_comments',
          {'entry_id': entry.id, 'group_key': c.key, 'comment': c.value},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<LogbookEntry>> fetchRecentEntries({int limit = 5}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'logbook_entries',
      orderBy: 'entry_timestamp DESC',
      limit: limit,
    );

    final entries = <LogbookEntry>[];
    for (final row in rows) {
      final id = row['id'] as String;
      final paramRows = await db.query(
        'parameter_values',
        where: 'entry_id = ?',
        whereArgs: [id],
      );
      final values = <String, String>{
        for (final p in paramRows) p['param_key'] as String: (p['value'] as String?) ?? '',
      };
      final paramPhotos = <String, String>{
        for (final p in paramRows)
          if (p['photo_path'] != null) p['param_key'] as String: p['photo_path'] as String,
      };

      final commentRows = await db.query(
        'group_comments',
        where: 'entry_id = ?',
        whereArgs: [id],
      );
      final groupComments = <String, String>{
        for (final c in commentRows) c['group_key'] as String: (c['comment'] as String?) ?? '',
      };

      entries.add(LogbookEntry(
        id: id,
        engineId: row['engine_id'] as String,
        generatorNumber: row['generator_number'] as int?,
        readingSlot: row['reading_slot'] as String?,
        timestamp: DateTime.parse(row['entry_timestamp'] as String),
        notes: row['notes'] as String?,
        signaturePath: row['signature_path'] as String?,
        photoPath: row['photo_path'] as String?,
        pdfPath: row['pdf_path'] as String?,
        hmiPhotoPath: row['hmi_photo_path'] as String?,
        synced: (row['synced'] as int) == 1,
        paramValues: values,
        paramPhotos: paramPhotos,
        groupComments: groupComments,
      ));
    }
    return entries;
  }
}
