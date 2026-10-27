import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Singleton wrapper around the sqflite database handle.
///
/// Two tables:
///  - logbook_entries: one row per submitted entry (metadata + file paths)
///  - parameter_values: one row per (entry, parameter) pair, so the form
///    schema can change over time without a migration for every new field.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _init();
    return _db!;
  }

  Future<Database> _init() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'logbridge.db');
    return openDatabase(
      path,
      version: 8,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE logbook_entries (
            id TEXT PRIMARY KEY,
            engine_id TEXT NOT NULL,
            generator_number INTEGER,
            reading_slot TEXT,
            entry_timestamp TEXT NOT NULL,
            notes TEXT,
            signature_path TEXT,
            photo_path TEXT,
            pdf_path TEXT,
            hmi_photo_path TEXT,
            operator_name TEXT,
            biometric_verified INTEGER NOT NULL DEFAULT 0,
            synced INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE parameter_values (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entry_id TEXT NOT NULL,
            param_key TEXT NOT NULL,
            param_category TEXT NOT NULL,
            value TEXT,
            photo_path TEXT,
            FOREIGN KEY(entry_id) REFERENCES logbook_entries(id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE group_comments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entry_id TEXT NOT NULL,
            group_key TEXT NOT NULL,
            comment TEXT,
            UNIQUE(entry_id, group_key),
            FOREIGN KEY(entry_id) REFERENCES logbook_entries(id) ON DELETE CASCADE
          )
        ''');
        await _addSync(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Per-parameter gauge evidence photos, added alongside the whole-
          // entry photo/PDF/signature paths already on logbook_entries.
          await db.execute('ALTER TABLE parameter_values ADD COLUMN photo_path TEXT');
        }
        if (oldVersion < 3) {
          // One evidence photo of the whole remote HMI screen.
          await db.execute('ALTER TABLE logbook_entries ADD COLUMN hmi_photo_path TEXT');
        }
        if (oldVersion < 4) {
          // One comment per parameter group/panel (not per reading), plus
          // the ability to correct an individual reading after submission.
          await db.execute('''
            CREATE TABLE group_comments (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              entry_id TEXT NOT NULL,
              group_key TEXT NOT NULL,
              comment TEXT,
              UNIQUE(entry_id, group_key),
              FOREIGN KEY(entry_id) REFERENCES logbook_entries(id) ON DELETE CASCADE
            )
          ''');
        }
        if (oldVersion < 5) {
          // Which physical generator (1-4) an entry belongs to. NULL means
          // "predates this column" — treated as Generator 1 everywhere it's
          // read, so existing entries don't just disappear.
          await db.execute('ALTER TABLE logbook_entries ADD COLUMN generator_number INTEGER');
        }
        if (oldVersion < 6) {
          // Which of the day's two paper-log columns ('time' or 'noon') this
          // entry was taken for — chosen explicitly by the operator rather
          // than guessed from the clock. NULL on legacy rows; the daily log
          // table falls back to the old hour-based guess for those.
          await db.execute('ALTER TABLE logbook_entries ADD COLUMN reading_slot TEXT');
        }
        if (oldVersion < 7) {
          // Submission moved from a drawn signature to a real device
          // biometric check (fingerprint/face) — operator_name records WHO
          // authenticated (from the signed-in session), biometric_verified
          // records THAT it happened. Legacy rows default to unverified;
          // their old signature_path (still on the table, untouched) is
          // what proves those specific entries.
          await db.execute('ALTER TABLE logbook_entries ADD COLUMN operator_name TEXT');
          await db.execute('ALTER TABLE logbook_entries ADD COLUMN biometric_verified INTEGER NOT NULL DEFAULT 0');
        }
        if (oldVersion < 8) {
          await _addSync(db);
        }
      },
    );
  }

  /// Sync with the LogBridge server (design, sections 3 and 6): each entry is a server log
  /// (log_id, status), every value says whether a person checked it and what the reader read,
  /// and changes wait in an outbox until the server has them. Entries saved before this
  /// existed keep status 'local': they stay on this tablet.
  static Future<void> _addSync(Database db) async {
    await db.execute('ALTER TABLE logbook_entries ADD COLUMN log_id TEXT');
    await db.execute("ALTER TABLE logbook_entries ADD COLUMN status TEXT NOT NULL DEFAULT 'local'");
    await db.execute('ALTER TABLE logbook_entries ADD COLUMN reject_reason TEXT');
    await db.execute('ALTER TABLE parameter_values ADD COLUMN confirmed INTEGER NOT NULL DEFAULT 1');
    await db.execute('ALTER TABLE parameter_values ADD COLUMN ocr_value TEXT');
    // one operation each: log.upsert, reading.set, photo.meta, log.submit - with its own id, so a
    // retry never doubles anything
    await db.execute('''
      CREATE TABLE outbox (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        op_id TEXT NOT NULL UNIQUE,
        type TEXT NOT NULL,
        log_id TEXT,
        op TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    // photos and PDFs to send: details first (with the hash), then the file
    await db.execute('''
      CREATE TABLE sync_photos (
        id TEXT PRIMARY KEY,
        entry_id TEXT NOT NULL,
        log_id TEXT NOT NULL,
        path TEXT NOT NULL,
        mime TEXT NOT NULL,
        size INTEGER NOT NULL,
        sha256 TEXT NOT NULL,
        taken_at TEXT NOT NULL,
        meta_synced INTEGER NOT NULL DEFAULT 0,
        uploaded INTEGER NOT NULL DEFAULT 0,
        rejected TEXT
      )
    ''');
    // what the server refused, for the Sync tab
    await db.execute('''
      CREATE TABLE sync_refused (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        at TEXT NOT NULL,
        type TEXT NOT NULL,
        log_id TEXT,
        message TEXT NOT NULL
      )
    ''');
  }
}
