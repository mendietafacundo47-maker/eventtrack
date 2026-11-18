import '../entities/assignment.dart';
import '../entities/local_evidence.dart';
import '../entities/user.dart';

/// Persistencia mínima clave/valor (implementada por la base local).
abstract interface class KeyValueStore {
  Future<String?> readValue(String key);

  Future<void> writeValue(String key, String? value);
}

abstract interface class AuthRepository {
  /// Lanza [InvalidCredentialsException] o [NetworkException].
  Future<User> login({required String email, required String password});

  /// Sesión guardada en el dispositivo, si existe. Permite abrir la app sin
  /// conexión y seguir registrando evidencias.
  Future<User?> restoreSession();

  Future<void> logout();
}

class AssignmentsResult {
  const AssignmentsResult(this.assignments, {required this.fromCache});

  final List<Assignment> assignments;

  /// `true` si no se pudo consultar el servidor y se muestran datos guardados.
  final bool fromCache;
}

abstract interface class AssignmentRepository {
  /// Solo las asignaciones del usuario autenticado (P-03).
  Future<AssignmentsResult> getMyAssignments(String userId);

  Future<Assignment?> findCached(String userId, String assignmentId);
}

abstract interface class EvidenceRepository {
  Future<LocalEvidence> saveLocal(LocalEvidence evidence);

  Future<List<LocalEvidence>> getAll(String userId);

  /// Evidencias PENDING cuyo próximo intento ya venció.
  Future<List<LocalEvidence>> getDueForSync(String userId, DateTime now);

  Future<DateTime?> nextScheduledRetry(String userId);

  Future<void> markUploading(int localId);

  Future<void> markSynced(int localId, EvidenceReceipt receipt);

  Future<void> markRetry(
    int localId, {
    required int retryCount,
    required DateTime nextRetryAt,
    required String error,
  });

  Future<void> markFailed(int localId, String error);

  /// Devuelve a PENDING una evidencia FAILED para reintentarla manualmente.
  Future<void> resetForRetry(int localId);

  /// Recupera los envíos que quedaron en UPLOADING por un cierre inesperado.
  Future<int> recoverInterruptedUploads();

  Future<void> discard(LocalEvidence evidence);

  /// Envía la evidencia al backend (multipart + Idempotency-Key).
  Future<EvidenceReceipt> upload(LocalEvidence evidence);
}
