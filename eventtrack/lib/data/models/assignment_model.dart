import '../../domain/entities/assignment.dart';

/// Respuesta esperada de `GET /api/v1/me/assignments`:
///
/// ```json
/// {
///   "id": "asg-1", "status": "ACTIVE",
///   "activity": { "id": "act-1", "title": "...", "description": "...",
///                 "dueAt": "2026-11-12T18:00:00Z", "status": "PENDING" },
///   "event": { "id": "evt-1", "name": "...", "latitude": -21.53,
///              "longitude": -64.72 }
/// }
/// ```
class AssignmentModel {
  AssignmentModel._();

  static Assignment fromJson(Map<String, dynamic> json) {
    final activity = json['activity'] as Map<String, dynamic>;
    final event = json['event'] as Map<String, dynamic>;
    final due = activity['dueAt'] as String?;
    return Assignment(
      id: json['id'].toString(),
      activityId: activity['id'].toString(),
      activityTitle: activity['title'] as String,
      activityDescription: activity['description'] as String? ?? '',
      activityStatus: ActivityStatus.fromCode(activity['status'] as String?),
      dueAt: due == null ? null : DateTime.parse(due),
      eventId: event['id'].toString(),
      eventName: event['name'] as String,
      eventLatitude: (event['latitude'] as num?)?.toDouble(),
      eventLongitude: (event['longitude'] as num?)?.toDouble(),
    );
  }

  static Map<String, dynamic> toJson(Assignment a) => {
    'id': a.id,
    'activity': {
      'id': a.activityId,
      'title': a.activityTitle,
      'description': a.activityDescription,
      'dueAt': a.dueAt?.toUtc().toIso8601String(),
      'status': a.activityStatus.code,
    },
    'event': {
      'id': a.eventId,
      'name': a.eventName,
      'latitude': a.eventLatitude,
      'longitude': a.eventLongitude,
    },
  };
}
