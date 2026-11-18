import 'assignment.dart';
import 'user.dart';

/// Entidades del panel web administrativo (§4.1.4): eventos, actividades,
/// asignaciones, evidencias, revisiones, usuarios y reportes.

/// Estados de evento (§4.4.7).
enum EventStatus {
  draft('DRAFT', 'Borrador'),
  active('ACTIVE', 'Activo'),
  closed('CLOSED', 'Cerrado'),
  cancelled('CANCELLED', 'Cancelado');

  const EventStatus(this.code, this.label);

  final String code;
  final String label;

  static EventStatus fromCode(String? code) => EventStatus.values.firstWhere(
    (s) => s.code == code,
    orElse: () => EventStatus.draft,
  );

  /// Transiciones permitidas por el backend.
  List<EventStatus> get nextStatuses => switch (this) {
    EventStatus.draft => [EventStatus.active, EventStatus.cancelled],
    EventStatus.active => [EventStatus.closed, EventStatus.cancelled],
    EventStatus.closed || EventStatus.cancelled => const [],
  };

  /// Solo borrador o activo aceptan cambios operativos.
  bool get isOpen => this == EventStatus.draft || this == EventStatus.active;
}

/// Estado de revisión de una evidencia (§4.4.1 estado_revision).
enum ReviewStatus {
  pending('PENDING_REVIEW', 'Pendiente'),
  approved('APPROVED', 'Aprobada'),
  rejected('REJECTED', 'Rechazada');

  const ReviewStatus(this.code, this.label);

  final String code;
  final String label;

  static ReviewStatus fromCode(String? code) => ReviewStatus.values.firstWhere(
    (s) => s.code == code,
    orElse: () => ReviewStatus.pending,
  );
}

class Paged<T> {
  const Paged(this.items, this.total);

  final List<T> items;
  final int total;
}

class PanelEvent {
  const PanelEvent({
    required this.id,
    required this.name,
    required this.description,
    required this.locationName,
    required this.startsAt,
    required this.endsAt,
    required this.latitude,
    required this.longitude,
    required this.status,
    required this.organizerId,
    required this.organizerName,
    required this.activitiesTotal,
    required this.activitiesCompleted,
  });

  final String id;
  final String name;
  final String description;
  final String? locationName;
  final DateTime startsAt;
  final DateTime endsAt;
  final double? latitude;
  final double? longitude;
  final EventStatus status;
  final String organizerId;
  final String organizerName;
  final int activitiesTotal;
  final int activitiesCompleted;
}

/// Datos de alta/edición de un evento.
class EventDraft {
  const EventDraft({
    required this.name,
    required this.description,
    required this.locationName,
    required this.startsAt,
    required this.endsAt,
    this.latitude,
    this.longitude,
  });

  final String name;
  final String description;
  final String? locationName;
  final DateTime startsAt;
  final DateTime endsAt;
  final double? latitude;
  final double? longitude;
}

class ActivityResponsible {
  const ActivityResponsible({
    required this.assignmentId,
    required this.userId,
    required this.fullName,
  });

  final String assignmentId;
  final String userId;
  final String fullName;
}

class PanelActivity {
  const PanelActivity({
    required this.id,
    required this.eventId,
    required this.title,
    required this.description,
    required this.dueAt,
    required this.status,
    required this.responsibles,
    required this.evidencesTotal,
  });

  final String id;
  final String eventId;
  final String title;
  final String description;
  final DateTime? dueAt;
  final ActivityStatus status;
  final List<ActivityResponsible> responsibles;
  final int evidencesTotal;
}

class EvidenceReview {
  const EvidenceReview({
    required this.result,
    required this.comment,
    required this.reviewedAt,
    required this.reviewerName,
  });

  final ReviewStatus result;
  final String comment;
  final DateTime reviewedAt;
  final String reviewerName;
}

class EvidenceRecord {
  const EvidenceRecord({
    required this.id,
    required this.status,
    required this.activityId,
    required this.activityTitle,
    required this.activityStatus,
    required this.eventId,
    required this.eventName,
    required this.createdByName,
    required this.locationStatus,
    required this.latitude,
    required this.longitude,
    required this.accuracyM,
    required this.distanceToEventM,
    required this.notes,
    required this.capturedAt,
    required this.receivedAt,
    this.reviews = const [],
  });

  final String id;
  final ReviewStatus status;
  final String activityId;
  final String activityTitle;
  final ActivityStatus activityStatus;
  final String eventId;
  final String eventName;
  final String createdByName;
  final String locationStatus;
  final double? latitude;
  final double? longitude;
  final double? accuracyM;
  final double? distanceToEventM;
  final String notes;
  final DateTime capturedAt;
  final DateTime receivedAt;
  final List<EvidenceReview> reviews;

  bool get hasLocation => latitude != null && longitude != null;
}

class ManagedUser {
  const ManagedUser({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.active,
    required this.lastLoginAt,
  });

  final String id;
  final String fullName;
  final String email;
  final UserRole role;
  final bool active;
  final DateTime? lastLoginAt;
}

/// Responsable que se puede asignar a una actividad.
class AssignableUser {
  const AssignableUser({
    required this.id,
    required this.fullName,
    required this.email,
  });

  final String id;
  final String fullName;
  final String email;
}

class ReportItem {
  const ReportItem({
    required this.id,
    required this.title,
    required this.status,
    required this.dueAt,
    required this.responsibles,
    required this.evidencesTotal,
    required this.pendingReview,
    required this.approved,
    required this.rejected,
    required this.lastEvidenceAt,
  });

  final String id;
  final String title;
  final ActivityStatus status;
  final DateTime? dueAt;
  final List<String> responsibles;
  final int evidencesTotal;
  final int pendingReview;
  final int approved;
  final int rejected;
  final DateTime? lastEvidenceAt;
}

/// RF-17 / P-08: indicadores de un evento.
class EventReport {
  const EventReport({
    required this.event,
    required this.activitiesTotal,
    required this.activitiesOpen,
    required this.activitiesByStatus,
    required this.assignmentsActive,
    required this.evidencesTotal,
    required this.evidencesPending,
    required this.evidencesApproved,
    required this.evidencesRejected,
    required this.evidencesWithLocation,
    required this.evidencesWithoutLocation,
    required this.reviewsTotal,
    required this.completionRate,
    required this.items,
    required this.generatedAt,
  });

  final PanelEvent event;
  final int activitiesTotal;
  final int activitiesOpen;
  final Map<ActivityStatus, int> activitiesByStatus;
  final int assignmentsActive;
  final int evidencesTotal;
  final int evidencesPending;
  final int evidencesApproved;
  final int evidencesRejected;
  final int evidencesWithLocation;
  final int evidencesWithoutLocation;
  final int reviewsTotal;
  final double completionRate;
  final List<ReportItem> items;
  final DateTime generatedAt;
}
