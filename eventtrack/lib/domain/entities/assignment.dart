/// Estados de actividad (§4.4.7).
enum ActivityStatus {
  pending('PENDING', 'Pendiente'),
  inProgress('IN_PROGRESS', 'En ejecución'),
  submitted('SUBMITTED', 'Enviada'),
  completed('COMPLETED', 'Completada'),
  cancelled('CANCELLED', 'Cancelada');

  const ActivityStatus(this.code, this.label);

  final String code;
  final String label;

  static ActivityStatus fromCode(String? code) =>
      ActivityStatus.values.firstWhere(
        (s) => s.code == code?.toUpperCase(),
        orElse: () => ActivityStatus.pending,
      );

  /// RB-04: solo se registra evidencia sobre actividades vigentes.
  bool get acceptsEvidence =>
      this != ActivityStatus.completed && this != ActivityStatus.cancelled;
}

/// Asignación de una actividad al usuario autenticado, con los datos de la
/// actividad y su evento ya resueltos para mostrarlos sin conexión.
class Assignment {
  const Assignment({
    required this.id,
    required this.activityId,
    required this.activityTitle,
    required this.activityDescription,
    required this.activityStatus,
    required this.dueAt,
    required this.eventId,
    required this.eventName,
    this.eventLatitude,
    this.eventLongitude,
  });

  final String id;
  final String activityId;
  final String activityTitle;
  final String activityDescription;
  final ActivityStatus activityStatus;
  final DateTime? dueAt;
  final String eventId;
  final String eventName;

  /// Punto de referencia del evento, usado solo como indicador de
  /// consistencia (RB-11).
  final double? eventLatitude;
  final double? eventLongitude;

  bool get hasEventLocation => eventLatitude != null && eventLongitude != null;
}
