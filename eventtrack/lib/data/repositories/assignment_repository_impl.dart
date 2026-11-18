import '../../core/errors/app_exception.dart';
import '../../domain/entities/assignment.dart';
import '../../domain/repositories/repositories.dart';
import '../local/assignment_cache.dart';
import '../remote/remote_data_sources.dart';

class AssignmentRepositoryImpl implements AssignmentRepository {
  AssignmentRepositoryImpl(this._remote, this._cache);

  final RemoteDataSource _remote;
  final AssignmentCache _cache;

  @override
  Future<AssignmentsResult> getMyAssignments(String userId) async {
    try {
      final fresh = await _remote.myAssignments();
      await _cache.replaceAll(userId, fresh);
      return AssignmentsResult(fresh, fromCache: false);
    } on NetworkException {
      final cached = await _cache.getAll(userId);
      if (cached.isEmpty) rethrow;
      return AssignmentsResult(cached, fromCache: true);
    }
  }

  @override
  Future<Assignment?> findCached(String userId, String assignmentId) =>
      _cache.find(userId, assignmentId);
}
