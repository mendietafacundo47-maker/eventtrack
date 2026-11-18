import 'package:flutter/foundation.dart';

import '../../../core/errors/app_exception.dart';
import '../../../domain/entities/assignment.dart';
import '../../../domain/repositories/repositories.dart';

class ActivitiesController extends ChangeNotifier {
  ActivitiesController(this._repository);

  final AssignmentRepository _repository;

  String? _userId;
  List<Assignment> _all = const [];
  String _query = '';
  bool _loading = false;
  bool _fromCache = false;
  String? _error;

  bool get loading => _loading;
  bool get fromCache => _fromCache;
  String? get error => _error;
  String get query => _query;
  List<Assignment> get all => _all;

  List<Assignment> get visible {
    final q = _query.trim().toLowerCase();
    final list = q.isEmpty
        ? [..._all]
        : _all
              .where(
                (a) =>
                    a.activityTitle.toLowerCase().contains(q) ||
                    a.eventName.toLowerCase().contains(q),
              )
              .toList();
    // Vigentes primero, ordenadas por fecha límite.
    list.sort((a, b) {
      final byOpen =
          (b.activityStatus.acceptsEvidence ? 1 : 0) -
          (a.activityStatus.acceptsEvidence ? 1 : 0);
      if (byOpen != 0) return byOpen;
      return (a.dueAt ?? DateTime(9999)).compareTo(b.dueAt ?? DateTime(9999));
    });
    return list;
  }

  int countBy(ActivityStatus status) =>
      _all.where((a) => a.activityStatus == status).length;

  /// Se llama cuando cambia el usuario autenticado.
  void bindUser(String? userId) {
    if (userId == _userId) return;
    _userId = userId;
    _all = const [];
    _error = null;
    _fromCache = false;
    if (userId != null) load();
  }

  Future<void> load() async {
    final userId = _userId;
    if (userId == null || _loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _repository.getMyAssignments(userId);
      _all = result.assignments;
      _fromCache = result.fromCache;
    } on AppException catch (e) {
      _error = e.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void search(String value) {
    _query = value;
    notifyListeners();
  }

  Future<Assignment?> findById(String id) async {
    final inMemory = _all.where((a) => a.id == id).firstOrNull;
    if (inMemory != null || _userId == null) return inMemory;
    return _repository.findCached(_userId!, id);
  }
}
