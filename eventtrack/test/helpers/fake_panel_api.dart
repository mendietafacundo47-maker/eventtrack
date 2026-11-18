import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:eventtrack/data/local/session_storage.dart';
import 'package:eventtrack/data/remote/api_client.dart';
import 'package:eventtrack/data/remote/panel_api.dart';
import 'package:eventtrack/domain/entities/assignment.dart';
import 'package:eventtrack/domain/entities/panel.dart';
import 'package:eventtrack/domain/entities/user.dart';
import 'package:eventtrack/domain/repositories/repositories.dart';

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository(this.user);

  final User? user;

  @override
  Future<User> login({required String email, required String password}) async =>
      user!;

  @override
  Future<User?> restoreSession() async => user;

  @override
  Future<void> logout() async {}
}

const admin = User(
  id: 'u-admin',
  fullName: 'Ana Admin',
  email: 'admin@uajms.edu.bo',
  role: UserRole.admin,
);
const organizer = User(
  id: 'u-org',
  fullName: 'Oscar Organizador',
  email: 'org@uajms.edu.bo',
  role: UserRole.organizer,
);
const supervisor = User(
  id: 'u-sup',
  fullName: 'Sara Supervisora',
  email: 'sup@uajms.edu.bo',
  role: UserRole.supervisor,
);
const responsible = User(
  id: 'u-resp',
  fullName: 'Alex Mamani',
  email: 'alex@uajms.edu.bo',
  role: UserRole.responsible,
);

final sampleEvent = PanelEvent(
  id: 'evt-1',
  name: 'Congreso Universitario de Informática',
  description: 'Jornadas académicas',
  locationName: 'Auditorio de la Facultad de Tecnología',
  startsAt: DateTime.utc(2026, 11, 20, 13),
  endsAt: DateTime.utc(2026, 11, 21, 22),
  latitude: -21.5337,
  longitude: -64.7348,
  status: EventStatus.active,
  organizerId: organizer.id,
  organizerName: organizer.fullName,
  activitiesTotal: 3,
  activitiesCompleted: 1,
);

final sampleActivities = [
  PanelActivity(
    id: 'act-1',
    eventId: sampleEvent.id,
    title: 'Acreditación Zona A',
    description: 'Entrega de credenciales a expositores',
    dueAt: DateTime.utc(2026, 11, 20, 15),
    status: ActivityStatus.submitted,
    responsibles: const [
      ActivityResponsible(
        assignmentId: 'asg-1',
        userId: 'u-resp',
        fullName: 'Alex Mamani',
      ),
    ],
    evidencesTotal: 1,
  ),
  PanelActivity(
    id: 'act-2',
    eventId: sampleEvent.id,
    title: 'Control de Acceso',
    description: '',
    dueAt: null,
    status: ActivityStatus.pending,
    responsibles: const [],
    evidencesTotal: 0,
  ),
  PanelActivity(
    id: 'act-3',
    eventId: sampleEvent.id,
    title: 'Instalación de equipos de sonido en el auditorio principal',
    description: 'Prueba de micrófonos',
    dueAt: DateTime.utc(2026, 11, 20, 12),
    status: ActivityStatus.completed,
    responsibles: const [
      ActivityResponsible(
        assignmentId: 'asg-2',
        userId: 'u-r2',
        fullName: 'Juan Pérez',
      ),
      ActivityResponsible(
        assignmentId: 'asg-3',
        userId: 'u-r3',
        fullName: 'María Fernanda Gutiérrez',
      ),
    ],
    evidencesTotal: 2,
  ),
];

EvidenceRecord sampleEvidence({
  String id = 'ev-1',
  ReviewStatus status = ReviewStatus.pending,
  bool withGps = true,
}) => EvidenceRecord(
  id: id,
  status: status,
  activityId: 'act-1',
  activityTitle: 'Acreditación Zona A',
  activityStatus: ActivityStatus.submitted,
  eventId: sampleEvent.id,
  eventName: sampleEvent.name,
  createdByName: 'Alex Mamani',
  locationStatus: withGps ? 'AVAILABLE' : 'PERMISSION_DENIED',
  latitude: withGps ? -21.53 : null,
  longitude: withGps ? -64.72 : null,
  accuracyM: withGps ? 8 : null,
  distanceToEventM: withGps ? 120 : null,
  notes: 'Mesa de acreditación lista.',
  capturedAt: DateTime.utc(2026, 11, 12, 14, 30),
  receivedAt: DateTime.utc(2026, 11, 12, 14, 31),
);

/// PanelApi en memoria: registra las llamadas que modifican datos.
class FakePanelApi extends PanelApi {
  FakePanelApi() : super(ApiClient(session: SessionStorage(), dio: Dio()));

  final reviews = <(String, ReviewStatus, String)>[];
  List<EvidenceRecord> inbox = [
    sampleEvidence(),
    sampleEvidence(id: 'ev-2', withGps: false),
  ];

  @override
  Future<Paged<PanelEvent>> events({
    String? search,
    EventStatus? status,
    int limit = 20,
    int offset = 0,
  }) async => Paged([sampleEvent], 1);

  @override
  Future<List<PanelActivity>> activities(String eventId) async =>
      sampleActivities;

  @override
  Future<Paged<EvidenceRecord>> evidences({
    String? eventId,
    ReviewStatus? status,
    int limit = 20,
    int offset = 0,
  }) async {
    final items = inbox
        .where((e) => status == null || e.status == status)
        .toList();
    return Paged(items, items.length);
  }

  @override
  Future<EvidenceRecord> evidence(String id) async =>
      inbox.firstWhere((e) => e.id == id);

  @override
  Future<Uint8List> evidencePhoto(String id) async => base64Decode(
    // PNG de 1×1 píxel.
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  );

  @override
  Future<void> review(
    String evidenceId,
    ReviewStatus result,
    String comment,
  ) async {
    reviews.add((evidenceId, result, comment));
  }

  @override
  Future<EventReport> eventReport(String eventId) async => EventReport(
    event: sampleEvent,
    activitiesTotal: 3,
    activitiesOpen: 2,
    activitiesByStatus: {
      for (final s in ActivityStatus.values) s: 0,
      ActivityStatus.pending: 1,
      ActivityStatus.submitted: 1,
      ActivityStatus.completed: 1,
    },
    assignmentsActive: 3,
    evidencesTotal: 3,
    evidencesPending: 2,
    evidencesApproved: 1,
    evidencesRejected: 0,
    evidencesWithLocation: 2,
    evidencesWithoutLocation: 1,
    reviewsTotal: 1,
    completionRate: 33.3,
    items: [
      for (final a in sampleActivities)
        ReportItem(
          id: a.id,
          title: a.title,
          status: a.status,
          dueAt: a.dueAt,
          responsibles: a.responsibles.map((r) => r.fullName).toList(),
          evidencesTotal: a.evidencesTotal,
          pendingReview: 1,
          approved: 0,
          rejected: 0,
          lastEvidenceAt: DateTime.utc(2026, 11, 12, 14, 31),
        ),
    ],
    generatedAt: DateTime.utc(2026, 11, 16, 10),
  );

  @override
  Future<Paged<ManagedUser>> users({
    String? search,
    UserRole? role,
    int limit = 20,
    int offset = 0,
  }) async => Paged([
    for (final u in [admin, organizer, supervisor, responsible])
      ManagedUser(
        id: u.id,
        fullName: u.fullName,
        email: u.email,
        role: u.role,
        active: u != responsible,
        lastLoginAt: u == admin ? DateTime.utc(2026, 11, 16, 9) : null,
      ),
  ], 4);

  @override
  Future<List<AssignableUser>> assignableUsers() async => [
    AssignableUser(
      id: responsible.id,
      fullName: responsible.fullName,
      email: responsible.email,
    ),
  ];
}
