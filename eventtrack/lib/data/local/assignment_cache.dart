import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../domain/entities/assignment.dart';
import '../models/assignment_model.dart';
import 'app_database.dart';

/// Última lista de asignaciones recibida del servidor, para consultar las
/// tareas y registrar evidencias sin conexión.
class AssignmentCache {
  AssignmentCache(this._database);

  final AppDatabase _database;

  static const _table = AppDatabase.assignmentsTable;

  Future<void> replaceAll(String userId, List<Assignment> assignments) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.db.transaction((txn) async {
      await txn.delete(_table, where: 'user_id = ?', whereArgs: [userId]);
      final batch = txn.batch();
      for (final a in assignments) {
        batch.insert(_table, {
          'id': a.id,
          'user_id': userId,
          'json': jsonEncode(AssignmentModel.toJson(a)),
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Assignment>> getAll(String userId) async {
    final rows = await _database.db.query(
      _table,
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    return rows
        .map(
          (r) => AssignmentModel.fromJson(
            jsonDecode(r['json'] as String) as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<Assignment?> find(String userId, String id) async {
    final rows = await _database.db.query(
      _table,
      where: 'user_id = ? AND id = ?',
      whereArgs: [userId, id],
    );
    if (rows.isEmpty) return null;
    return AssignmentModel.fromJson(
      jsonDecode(rows.first['json'] as String) as Map<String, dynamic>,
    );
  }
}
