// Prueba de contrato del panel web contra el backend Node.js real: recorre el
// flujo optimizado (§3.1.2) con las mismas clases que usa el panel.
//
// Requiere el backend en ejecución con `npm run db:seed:demo`:
//
//   EVENTTRACK_API=http://localhost:3000/api/v1 flutter test test/panel_contract_test.dart
//
// Crea un evento de prueba propio y lo deja CERRADO al terminar.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:eventtrack/core/errors/app_exception.dart';
import 'package:eventtrack/data/local/session_storage.dart';
import 'package:eventtrack/data/remote/api_client.dart';
import 'package:eventtrack/data/remote/panel_api.dart';
import 'package:eventtrack/data/remote/remote_data_sources.dart';
import 'package:eventtrack/domain/entities/assignment.dart';
import 'package:eventtrack/domain/entities/geo_reading.dart';
import 'package:eventtrack/domain/entities/local_evidence.dart';
import 'package:eventtrack/domain/entities/panel.dart';
import 'package:eventtrack/domain/entities/user.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

class MemorySession extends SessionStorage {
  String? token;

  @override
  Future<String?> readToken() async => token;
}

/// Cliente autenticado como un usuario demo.
class Client {
  Client(String baseUrl) {
    final api = ApiClient(
      session: session,
      dio: Dio(BaseOptions(baseUrl: baseUrl)),
    );
    remote = RemoteDataSource(api);
    panel = PanelApi(api);
  }

  final session = MemorySession();
  late final RemoteDataSource remote;
  late final PanelApi panel;
  late User user;

  Future<void> login(String email) async {
    final res = await remote.login(email, 'Demo1234');
    session.token = res.accessToken;
    user = res.user;
  }
}

void main() {
  final baseUrl = Platform.environment['EVENTTRACK_API'];
  final skip = baseUrl == null ? 'Define EVENTTRACK_API para ejecutar' : null;

  late Client organizer;
  late Client supervisor;
  late Client responsible;
  late PanelEvent event;
  late PanelActivity activity;
  late String evidenceId;
  late Directory tmp;

  setUpAll(() async {
    if (baseUrl == null) return;
    organizer = Client(baseUrl);
    supervisor = Client(baseUrl);
    responsible = Client(baseUrl);
    await organizer.login('organizador@uajms.edu.bo');
    await supervisor.login('supervisor@uajms.edu.bo');
    await responsible.login('responsable@uajms.edu.bo');
    tmp = await Directory.systemTemp.createTemp('eventtrack_panel');
  });

  tearDownAll(() async {
    if (baseUrl == null) return;
    await tmp.delete(recursive: true);
  });

  test('TC-05: fin anterior al inicio → el backend rechaza', () async {
    final now = DateTime.now();
    await expectLater(
      organizer.panel.createEvent(
        EventDraft(
          name: 'Evento inválido',
          description: '',
          locationName: null,
          startsAt: now,
          endsAt: now.subtract(const Duration(hours: 1)),
        ),
        activate: true,
      ),
      throwsA(isA<PermanentException>()),
    );
  }, skip: skip);

  test('TC-04: el organizador crea un evento activo', () async {
    final start = DateTime.now().add(const Duration(days: 1));
    event = await organizer.panel.createEvent(
      EventDraft(
        name:
            'Prueba de contrato del panel ${DateTime.now().millisecondsSinceEpoch}',
        description: 'Creado por panel_contract_test.dart',
        locationName: 'Campus El Tejar',
        startsAt: start,
        endsAt: start.add(const Duration(hours: 6)),
        latitude: -21.5337,
        longitude: -64.7348,
      ),
      activate: true,
    );
    expect(event.status, EventStatus.active);
    expect(event.organizerId, organizer.user.id);
    expect(event.latitude, -21.5337);

    final page = await organizer.panel.events(search: 'Prueba de contrato');
    expect(page.items.map((e) => e.id), contains(event.id));
  }, skip: skip);

  test('RF-06/RF-07: crea actividad y asigna al responsable', () async {
    activity = await organizer.panel.createActivity(
      event.id,
      title: 'Verificar señalización',
      description: 'Carteles en accesos',
      dueAt: DateTime.now().add(const Duration(days: 1)),
    );
    expect(activity.status, ActivityStatus.pending);

    final candidates = await organizer.panel.assignableUsers();
    final target = candidates.firstWhere(
      (u) => u.email == 'responsable@uajms.edu.bo',
    );
    await organizer.panel.assign(activity.id, target.id);

    final list = await organizer.panel.activities(event.id);
    final updated = list.firstWhere((a) => a.id == activity.id);
    expect(updated.responsibles.single.fullName, responsible.user.fullName);
  }, skip: skip);

  test('TC-03: el supervisor no puede crear eventos ni ver usuarios', () async {
    await expectLater(
      supervisor.panel.users(),
      throwsA(isA<PermanentException>()),
    );
    await expectLater(
      supervisor.panel.assignableUsers(),
      throwsA(isA<PermanentException>()),
    );
  }, skip: skip);

  test('el responsable envía evidencia desde la app (multipart)', () async {
    final mine = await responsible.remote.myAssignments();
    final assignment = mine.firstWhere((a) => a.activityId == activity.id);
    final photo = File('${tmp.path}/foto.jpg')
      ..writeAsBytesSync([0xff, 0xd8, 0xff, 0xe0, ...List.filled(512, 7)]);
    final receipt = await responsible.remote.uploadEvidence(
      LocalEvidence(
        clientUuid: const Uuid().v4(),
        assignmentId: assignment.id,
        userId: responsible.user.id,
        activityTitle: assignment.activityTitle,
        eventName: assignment.eventName,
        photoPath: photo.path,
        location: GeoReading.available(
          latitude: -21.5338,
          longitude: -64.7349,
          accuracyM: 7,
        ),
        capturedAt: DateTime.now().toUtc(),
        notes: 'Señalización instalada',
      ),
    );
    evidenceId = receipt.evidenceId;
  }, skip: skip);

  test('P-07: el supervisor ve la evidencia con foto y metadatos', () async {
    final inbox = await supervisor.panel.evidences(
      eventId: event.id,
      status: ReviewStatus.pending,
    );
    final item = inbox.items.single;
    expect(item.id, evidenceId);
    expect(item.activityTitle, 'Verificar señalización');
    expect(item.createdByName, responsible.user.fullName);
    expect(item.hasLocation, isTrue);
    expect(item.accuracyM, 7);
    expect(item.distanceToEventM, lessThan(50));

    final photo = await supervisor.panel.evidencePhoto(evidenceId);
    expect(photo.take(3), [0xff, 0xd8, 0xff]);
  }, skip: skip);

  test(
    'TC-20 / TC-19: rechazo exige motivo; la aprobación queda registrada',
    () async {
      await expectLater(
        supervisor.panel.review(evidenceId, ReviewStatus.rejected, ''),
        throwsA(isA<PermanentException>()),
      );
      await supervisor.panel.review(
        evidenceId,
        ReviewStatus.approved,
        'Correcto',
      );

      final detail = await supervisor.panel.evidence(evidenceId);
      expect(detail.status, ReviewStatus.approved);
      expect(detail.reviews.single.reviewerName, supervisor.user.fullName);
      expect(detail.activityStatus, ActivityStatus.completed);
    },
    skip: skip,
  );

  test('TC-21: el reporte refleja los registros', () async {
    final r = await supervisor.panel.eventReport(event.id);
    expect(r.activitiesTotal, 1);
    expect(r.activitiesByStatus[ActivityStatus.completed], 1);
    expect(r.activitiesOpen, 0);
    expect(r.completionRate, 100);
    expect(r.assignmentsActive, 1);
    expect(r.evidencesTotal, 1);
    expect(r.evidencesApproved, 1);
    expect(r.evidencesWithLocation, 1);
    expect(r.reviewsTotal, 1);
    expect(r.items.single.responsibles, [responsible.user.fullName]);
  }, skip: skip);

  test('el organizador cierra el evento de prueba', () async {
    final closed = await organizer.panel.changeEventStatus(
      event.id,
      EventStatus.closed,
    );
    expect(closed.status, EventStatus.closed);
  }, skip: skip);
}
