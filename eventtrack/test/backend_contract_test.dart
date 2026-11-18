// Prueba de contrato contra el backend Node.js real. Usa las mismas clases
// de datos que la app (ApiClient, RemoteDataSource, modelos).
//
// Requiere el backend en ejecución con `npm run db:seed:demo`:
//
//   EVENTTRACK_API=http://localhost:3000/api/v1 flutter test test/backend_contract_test.dart
//
// Sin EVENTTRACK_API la prueba se omite.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:eventtrack/core/errors/app_exception.dart';
import 'package:eventtrack/data/local/session_storage.dart';
import 'package:eventtrack/data/remote/api_client.dart';
import 'package:eventtrack/data/remote/remote_data_sources.dart';
import 'package:eventtrack/domain/entities/assignment.dart';
import 'package:eventtrack/domain/entities/geo_reading.dart';
import 'package:eventtrack/domain/entities/local_evidence.dart';
import 'package:eventtrack/domain/entities/user.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

class MemorySession extends SessionStorage {
  String? token;

  @override
  Future<String?> readToken() async => token;
}

void main() {
  final baseUrl = Platform.environment['EVENTTRACK_API'];
  final skip = baseUrl == null ? 'Define EVENTTRACK_API para ejecutar' : null;

  late MemorySession session;
  late RemoteDataSource remote;
  late Directory tmp;
  var unauthorizedCalls = 0;

  setUpAll(() async {
    session = MemorySession();
    remote = RemoteDataSource(
      ApiClient(
        session: session,
        onUnauthorized: () => unauthorizedCalls++,
        dio: Dio(BaseOptions(baseUrl: baseUrl ?? '')),
      ),
    );
    tmp = await Directory.systemTemp.createTemp('eventtrack_contract');
  });

  tearDownAll(() => tmp.delete(recursive: true));

  test('TC-02: credenciales inválidas → InvalidCredentialsException', () async {
    await expectLater(
      remote.login('responsable@uajms.edu.bo', 'incorrecta'),
      throwsA(isA<InvalidCredentialsException>()),
    );
  }, skip: skip);

  test('sin token, /me/assignments → 401 y aviso de sesión expirada', () async {
    session.token = null;
    await expectLater(
      remote.myAssignments(),
      throwsA(isA<UnauthorizedException>()),
    );
    expect(unauthorizedCalls, 1);
  }, skip: skip);

  late List<Assignment> assignments;

  test('TC-01: login devuelve token y usuario con rol', () async {
    final res = await remote.login('responsable@uajms.edu.bo', 'Demo1234');
    expect(res.accessToken, isNotEmpty);
    expect(res.user.role, UserRole.responsible);
    expect(res.user.fullName, 'Responsable de Prueba');
    session.token = res.accessToken;
  }, skip: skip);

  test('P-03: /me/assignments se convierte en Assignment', () async {
    assignments = await remote.myAssignments();
    expect(assignments, isNotEmpty);
    final a = assignments.first;
    expect(a.activityTitle, isNotEmpty);
    expect(a.eventName, isNotEmpty);
    expect(a.hasEventLocation, isTrue);
  }, skip: skip);

  test(
    'TC-14/TC-15: envío multipart e idempotencia con el backend real',
    () async {
      final open = assignments.firstWhere(
        (a) => a.activityStatus.acceptsEvidence,
      );
      final photo = File('${tmp.path}/foto.jpg')
        ..writeAsBytesSync([0xff, 0xd8, 0xff, 0xe0, ...List.filled(256, 7)]);
      final evidence = LocalEvidence(
        clientUuid: const Uuid().v4(),
        assignmentId: open.id,
        userId: 'n/a',
        activityTitle: open.activityTitle,
        eventName: open.eventName,
        photoPath: photo.path,
        location: const GeoReading.available(
          latitude: -21.5338,
          longitude: -64.7349,
          accuracyM: 7,
        ),
        capturedAt: DateTime.now().toUtc(),
        notes: 'Prueba de contrato Flutter ↔ backend',
      );

      final first = await remote.uploadEvidence(evidence);
      final retry = await remote.uploadEvidence(evidence);
      expect(retry.evidenceId, first.evidenceId);
      expect(first.status, 'PENDING_REVIEW');

      // RB-07: sin GPS también se acepta, con coordenadas nulas.
      final noGps = await remote.uploadEvidence(
        LocalEvidence(
          clientUuid: const Uuid().v4(),
          assignmentId: open.id,
          userId: 'n/a',
          activityTitle: open.activityTitle,
          eventName: open.eventName,
          photoPath: photo.path,
          location: const GeoReading.missing(LocationStatus.permissionDenied),
          capturedAt: DateTime.now().toUtc(),
          notes: '',
        ),
      );
      expect(noGps.evidenceId, isNot(first.evidenceId));
    },
    skip: skip,
  );

  test(
    'TC-07: asignación ajena → error permanente (no se reintenta)',
    () async {
      final photo = File('${tmp.path}/foto.jpg');
      await expectLater(
        remote.uploadEvidence(
          LocalEvidence(
            clientUuid: const Uuid().v4(),
            assignmentId: const Uuid().v4(),
            userId: 'n/a',
            activityTitle: 'x',
            eventName: 'x',
            photoPath: photo.path,
            location: const GeoReading.missing(LocationStatus.unavailable),
            capturedAt: DateTime.now().toUtc(),
            notes: '',
          ),
        ),
        throwsA(
          isA<PermanentException>().having((e) => e.code, 'code', 'HTTP_403'),
        ),
      );
    },
    skip: skip,
  );
}
