import '../../domain/entities/geo_reading.dart';
import '../../domain/entities/local_evidence.dart';

/// Conversión entre [LocalEvidence], filas SQLite y el JSON de `metadata`
/// que espera `POST /api/v1/evidences` (§4.3.5).
class EvidenceModel {
  EvidenceModel._();

  static Map<String, Object?> toRow(LocalEvidence e) => {
    if (e.localId != null) 'local_id': e.localId,
    'client_uuid': e.clientUuid,
    'assignment_id': e.assignmentId,
    'user_id': e.userId,
    'activity_title': e.activityTitle,
    'event_name': e.eventName,
    'photo_path': e.photoPath,
    'latitude': e.location.latitude,
    'longitude': e.location.longitude,
    'accuracy_m': e.location.accuracyM,
    'location_status': e.location.status.code,
    'captured_at': e.capturedAt.toUtc().toIso8601String(),
    'notes': e.notes,
    'sync_status': e.syncStatus.code,
    'retry_count': e.retryCount,
    'next_retry_at': e.nextRetryAt?.toUtc().toIso8601String(),
    'last_error': e.lastError,
    'server_evidence_id': e.serverEvidenceId,
    'server_received_at': e.serverReceivedAt?.toUtc().toIso8601String(),
  };

  static LocalEvidence fromRow(Map<String, Object?> row) {
    final status = LocationStatus.fromCode(row['location_status'] as String?);
    final lat = (row['latitude'] as num?)?.toDouble();
    final lng = (row['longitude'] as num?)?.toDouble();
    final location =
        status == LocationStatus.available && lat != null && lng != null
        ? GeoReading.available(
            latitude: lat,
            longitude: lng,
            accuracyM: (row['accuracy_m'] as num?)?.toDouble(),
          )
        : GeoReading.missing(
            status == LocationStatus.available
                ? LocationStatus.unavailable
                : status,
          );

    return LocalEvidence(
      localId: row['local_id'] as int,
      clientUuid: row['client_uuid'] as String,
      assignmentId: row['assignment_id'] as String,
      userId: row['user_id'] as String,
      activityTitle: row['activity_title'] as String,
      eventName: row['event_name'] as String,
      photoPath: row['photo_path'] as String,
      location: location,
      capturedAt: DateTime.parse(row['captured_at'] as String),
      notes: row['notes'] as String? ?? '',
      syncStatus: SyncStatus.fromCode(row['sync_status'] as String),
      retryCount: row['retry_count'] as int? ?? 0,
      nextRetryAt: _date(row['next_retry_at']),
      lastError: row['last_error'] as String?,
      serverEvidenceId: row['server_evidence_id'] as String?,
      serverReceivedAt: _date(row['server_received_at']),
    );
  }

  static Map<String, Object?> toMetadataJson(LocalEvidence e) => {
    'clientUuid': e.clientUuid,
    'assignmentId': e.assignmentId,
    'latitude': e.location.latitude,
    'longitude': e.location.longitude,
    'accuracyM': e.location.accuracyM,
    'locationStatus': e.location.status.code,
    'capturedAt': e.capturedAt.toUtc().toIso8601String(),
    'notes': e.notes,
  };

  static EvidenceReceipt receiptFromJson(Map<String, dynamic> json) =>
      EvidenceReceipt(
        evidenceId: json['id'].toString(),
        status: json['status'] as String? ?? 'RECEIVED',
        receivedAt: DateTime.parse(json['receivedAt'] as String),
      );

  static DateTime? _date(Object? v) => v is String ? DateTime.parse(v) : null;
}
