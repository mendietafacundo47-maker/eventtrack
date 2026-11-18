import '../../domain/entities/assignment.dart';
import '../../domain/entities/panel.dart';
import '../../domain/entities/user.dart';

typedef Json = Map<String, dynamic>;

DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String);
double? _double(Object? v) => (v as num?)?.toDouble();
int _int(Object? v) => (v as num?)?.toInt() ?? 0;

/// Conversión de las respuestas JSON del backend (§4.5.4) a entidades del
/// panel web.
class PanelModels {
  PanelModels._();

  static PanelEvent event(Json j) {
    final organizer = j['organizer'] as Json;
    final activities = j['activities'] as Json? ?? const {};
    return PanelEvent(
      id: j['id'] as String,
      name: j['name'] as String,
      description: j['description'] as String? ?? '',
      locationName: j['locationName'] as String?,
      startsAt: _date(j['startsAt'])!,
      endsAt: _date(j['endsAt'])!,
      latitude: _double(j['latitude']),
      longitude: _double(j['longitude']),
      status: EventStatus.fromCode(j['status'] as String?),
      organizerId: organizer['id'] as String,
      organizerName: organizer['fullName'] as String,
      activitiesTotal: _int(activities['total']),
      activitiesCompleted: _int(activities['completed']),
    );
  }

  static Json eventDraft(EventDraft d) => {
    'name': d.name,
    'description': d.description,
    'locationName': d.locationName,
    'startsAt': d.startsAt.toUtc().toIso8601String(),
    'endsAt': d.endsAt.toUtc().toIso8601String(),
    'latitude': d.latitude,
    'longitude': d.longitude,
  };

  static PanelActivity activity(Json j) => PanelActivity(
    id: j['id'] as String,
    eventId: j['eventId'] as String,
    title: j['title'] as String,
    description: j['description'] as String? ?? '',
    dueAt: _date(j['dueAt']),
    status: ActivityStatus.fromCode(j['status'] as String?),
    responsibles: (j['responsibles'] as List? ?? const [])
        .cast<Json>()
        .map(
          (r) => ActivityResponsible(
            assignmentId: r['assignmentId'] as String,
            userId: r['userId'] as String,
            fullName: r['fullName'] as String,
          ),
        )
        .toList(),
    evidencesTotal: _int(j['evidencesTotal']),
  );

  static EvidenceRecord evidence(Json j) {
    final activity = j['activity'] as Json;
    final event = j['event'] as Json;
    final location = j['location'] as Json;
    return EvidenceRecord(
      id: j['id'] as String,
      status: ReviewStatus.fromCode(j['status'] as String?),
      activityId: activity['id'] as String,
      activityTitle: activity['title'] as String,
      activityStatus: ActivityStatus.fromCode(activity['status'] as String?),
      eventId: event['id'] as String,
      eventName: event['name'] as String,
      createdByName: (j['createdBy'] as Json)['fullName'] as String,
      locationStatus: location['status'] as String? ?? 'UNAVAILABLE',
      latitude: _double(location['latitude']),
      longitude: _double(location['longitude']),
      accuracyM: _double(location['accuracyM']),
      distanceToEventM: _double(location['distanceToEventM']),
      notes: j['notes'] as String? ?? '',
      capturedAt: _date(j['capturedAt'])!,
      receivedAt: _date(j['receivedAt'])!,
      reviews: (j['reviews'] as List? ?? const [])
          .cast<Json>()
          .map(
            (r) => EvidenceReview(
              result: ReviewStatus.fromCode(r['result'] as String?),
              comment: r['comment'] as String? ?? '',
              reviewedAt: _date(r['reviewedAt'])!,
              reviewerName: (r['reviewer'] as Json)['fullName'] as String,
            ),
          )
          .toList(),
    );
  }

  static ManagedUser user(Json j) => ManagedUser(
    id: j['id'] as String,
    fullName: j['fullName'] as String,
    email: j['email'] as String,
    role: UserRole.fromCode(j['role'] as String?),
    active: j['active'] as bool? ?? true,
    lastLoginAt: _date(j['lastLoginAt']),
  );

  static AssignableUser assignable(Json j) => AssignableUser(
    id: j['id'] as String,
    fullName: j['fullName'] as String,
    email: j['email'] as String,
  );

  static EventReport report(Json j) {
    final activities = j['activities'] as Json;
    final byStatus = activities['byStatus'] as Json;
    final evidences = j['evidences'] as Json;
    return EventReport(
      event: event(j['event'] as Json),
      activitiesTotal: _int(activities['total']),
      activitiesOpen: _int(activities['open']),
      activitiesByStatus: {
        for (final s in ActivityStatus.values) s: _int(byStatus[s.code]),
      },
      assignmentsActive: _int((j['assignments'] as Json)['active']),
      evidencesTotal: _int(evidences['total']),
      evidencesPending: _int(evidences['pendingReview']),
      evidencesApproved: _int(evidences['approved']),
      evidencesRejected: _int(evidences['rejected']),
      evidencesWithLocation: _int(evidences['withLocation']),
      evidencesWithoutLocation: _int(evidences['withoutLocation']),
      reviewsTotal: _int((j['reviews'] as Json)['total']),
      completionRate: _double(j['completionRate']) ?? 0,
      items: (j['items'] as List).cast<Json>().map((i) {
        final ev = i['evidences'] as Json;
        return ReportItem(
          id: i['id'] as String,
          title: i['title'] as String,
          status: ActivityStatus.fromCode(i['status'] as String?),
          dueAt: _date(i['dueAt']),
          responsibles: (i['responsibles'] as List).cast<String>(),
          evidencesTotal: _int(ev['total']),
          pendingReview: _int(ev['pendingReview']),
          approved: _int(ev['approved']),
          rejected: _int(ev['rejected']),
          lastEvidenceAt: _date(i['lastEvidenceAt']),
        );
      }).toList(),
      generatedAt: _date(j['generatedAt'])!,
    );
  }
}
