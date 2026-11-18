import 'geo_reading.dart';

/// Estado de una evidencia en la cola local (§4.3.3, §4.4.7).
enum SyncStatus {
  pending('PENDING', 'Pendiente'),
  uploading('UPLOADING', 'Enviando'),
  synced('SYNCED', 'Sincronizada'),
  failed('FAILED', 'Error');

  const SyncStatus(this.code, this.label);

  final String code;
  final String label;

  static SyncStatus fromCode(String code) =>
      SyncStatus.values.firstWhere((s) => s.code == code);
}

/// Evidencia registrada en el dispositivo. Se guarda primero localmente y
/// luego se sincroniza; `clientUuid` es la clave de idempotencia (RB-10).
class LocalEvidence {
  const LocalEvidence({
    this.localId,
    required this.clientUuid,
    required this.assignmentId,
    required this.userId,
    required this.activityTitle,
    required this.eventName,
    required this.photoPath,
    required this.location,
    required this.capturedAt,
    required this.notes,
    this.syncStatus = SyncStatus.pending,
    this.retryCount = 0,
    this.nextRetryAt,
    this.lastError,
    this.serverEvidenceId,
    this.serverReceivedAt,
  });

  final int? localId;
  final String clientUuid;
  final String assignmentId;
  final String userId;

  /// Copias desnormalizadas para mostrar la cola sin conexión.
  final String activityTitle;
  final String eventName;

  /// Ruta del archivo en el almacenamiento privado de la app. La imagen no se
  /// guarda como Base64 en SQLite (§4.3.3).
  final String photoPath;
  final GeoReading location;

  /// Hora de captura del dispositivo, en UTC. La hora de recepción del
  /// servidor se guarda por separado (§4.3.5).
  final DateTime capturedAt;
  final String notes;

  final SyncStatus syncStatus;
  final int retryCount;
  final DateTime? nextRetryAt;
  final String? lastError;
  final String? serverEvidenceId;
  final DateTime? serverReceivedAt;
}

/// Confirmación del backend tras recibir una evidencia.
class EvidenceReceipt {
  const EvidenceReceipt({
    required this.evidenceId,
    required this.status,
    required this.receivedAt,
  });

  final String evidenceId;
  final String status;
  final DateTime receivedAt;
}
