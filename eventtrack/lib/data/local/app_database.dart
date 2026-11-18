import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../domain/repositories/repositories.dart';

/// Base de datos SQLite local de la app Android (§4.3.3).
///
/// Las migraciones se versionan con `version` + `onUpgrade`; nunca se
/// borran tablas con evidencias pendientes (RNF-07).
class AppDatabase implements KeyValueStore {
  AppDatabase._(this.db);

  final Database db;

  static const _fileName = 'eventtrack.db';
  static const _version = 1;

  static const evidencesTable = 'evidences';
  static const assignmentsTable = 'cached_assignments';
  static const kvTable = 'kv';

  /// [factory] y [path] permiten usar una base en memoria en pruebas.
  static Future<AppDatabase> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final dbFactory = factory ?? databaseFactory;
    final dbPath =
        path ?? p.join(await dbFactory.getDatabasesPath(), _fileName);
    final db = await dbFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: _version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) => _createV1(db),
      ),
    );
    return AppDatabase._(db);
  }

  static Future<void> _createV1(Database db) async {
    final batch = db.batch();
    batch.execute('''
      CREATE TABLE $evidencesTable (
        local_id           INTEGER PRIMARY KEY AUTOINCREMENT,
        client_uuid        TEXT    NOT NULL UNIQUE,
        assignment_id      TEXT    NOT NULL,
        user_id            TEXT    NOT NULL,
        activity_title     TEXT    NOT NULL,
        event_name         TEXT    NOT NULL,
        photo_path         TEXT    NOT NULL,
        latitude           REAL,
        longitude          REAL,
        accuracy_m         REAL,
        location_status    TEXT    NOT NULL,
        captured_at        TEXT    NOT NULL,
        notes              TEXT    NOT NULL DEFAULT '',
        sync_status        TEXT    NOT NULL DEFAULT 'PENDING'
          CHECK (sync_status IN ('PENDING','UPLOADING','SYNCED','FAILED')),
        retry_count        INTEGER NOT NULL DEFAULT 0,
        next_retry_at      TEXT,
        last_error         TEXT,
        server_evidence_id TEXT,
        server_received_at TEXT,
        created_at         TEXT    NOT NULL,
        CHECK (latitude  IS NULL OR (latitude  BETWEEN -90  AND 90)),
        CHECK (longitude IS NULL OR (longitude BETWEEN -180 AND 180))
      )
    ''');
    batch.execute(
      'CREATE INDEX idx_evidences_user_status '
      'ON $evidencesTable (user_id, sync_status)',
    );
    batch.execute('''
      CREATE TABLE $assignmentsTable (
        id         TEXT NOT NULL,
        user_id    TEXT NOT NULL,
        json       TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (user_id, id)
      )
    ''');
    batch.execute('''
      CREATE TABLE $kvTable (
        key   TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
    await batch.commit(noResult: true);
  }

  @override
  Future<String?> readValue(String key) async {
    final rows = await db.query(kvTable, where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  @override
  Future<void> writeValue(String key, String? value) => db.insert(kvTable, {
    'key': key,
    'value': value,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> close() => db.close();
}
