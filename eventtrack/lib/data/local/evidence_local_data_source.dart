import 'package:sqflite/sqflite.dart';

import '../../domain/entities/local_evidence.dart';
import '../models/evidence_model.dart';
import 'app_database.dart';

/// Cola local de evidencias. Los cambios de estado solo ocurren tras una
/// respuesta concreta del servidor (§4.3.4).
class EvidenceLocalDataSource {
  EvidenceLocalDataSource(this._database);

  final AppDatabase _database;

  Database get _db => _database.db;
  static const _table = AppDatabase.evidencesTable;

  Future<int> insert(LocalEvidence evidence) {
    final row = EvidenceModel.toRow(evidence)
      ..['created_at'] = DateTime.now().toUtc().toIso8601String();
    return _db.insert(_table, row, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<LocalEvidence?> getById(int localId) async {
    final rows = await _db.query(
      _table,
      where: 'local_id = ?',
      whereArgs: [localId],
    );
    return rows.isEmpty ? null : EvidenceModel.fromRow(rows.first);
  }

  Future<List<LocalEvidence>> getAll(String userId) async {
    final rows = await _db.query(
      _table,
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'captured_at DESC',
    );
    return rows.map(EvidenceModel.fromRow).toList();
  }

  Future<List<LocalEvidence>> getDue(String userId, DateTime now) async {
    final rows = await _db.query(
      _table,
      where:
          "user_id = ? AND sync_status = 'PENDING' "
          'AND (next_retry_at IS NULL OR next_retry_at <= ?)',
      whereArgs: [userId, now.toUtc().toIso8601String()],
      orderBy: 'captured_at ASC',
    );
    return rows.map(EvidenceModel.fromRow).toList();
  }

  Future<DateTime?> nextScheduledRetry(String userId) async {
    final rows = await _db.rawQuery(
      'SELECT MIN(next_retry_at) AS next FROM $_table '
      "WHERE user_id = ? AND sync_status = 'PENDING' "
      'AND next_retry_at IS NOT NULL',
      [userId],
    );
    final next = rows.first['next'] as String?;
    return next == null ? null : DateTime.parse(next);
  }

  Future<void> update(int localId, Map<String, Object?> values) =>
      _db.update(_table, values, where: 'local_id = ?', whereArgs: [localId]);

  Future<int> resetUploading() => _db.update(
    _table,
    {'sync_status': SyncStatus.pending.code, 'next_retry_at': null},
    where: 'sync_status = ?',
    whereArgs: [SyncStatus.uploading.code],
  );

  Future<void> delete(int localId) =>
      _db.delete(_table, where: 'local_id = ?', whereArgs: [localId]);
}
