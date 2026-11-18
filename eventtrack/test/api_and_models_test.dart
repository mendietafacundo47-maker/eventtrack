import 'package:dio/dio.dart';
import 'package:eventtrack/core/errors/app_exception.dart';
import 'package:eventtrack/data/models/assignment_model.dart';
import 'package:eventtrack/data/models/evidence_model.dart';
import 'package:eventtrack/data/remote/api_client.dart';
import 'package:eventtrack/domain/entities/assignment.dart';
import 'package:eventtrack/domain/entities/geo_reading.dart';
import 'package:eventtrack/domain/entities/local_evidence.dart';
import 'package:flutter_test/flutter_test.dart';

DioException _http(int status) {
  final o = RequestOptions(path: '/evidences');
  return DioException.badResponse(
    statusCode: status,
    requestOptions: o,
    response: Response(requestOptions: o, statusCode: status),
  );
}

void main() {
  group('Clasificación de errores HTTP', () {
    test('errores de red y 5xx son transitorios', () {
      final o = RequestOptions(path: '/x');
      expect(
        mapDioException(
          DioException.connectionError(requestOptions: o, reason: 'x'),
        ),
        isA<NetworkException>(),
      );
      expect(
        mapDioException(
          DioException.receiveTimeout(
            timeout: Duration.zero,
            requestOptions: o,
          ),
        ),
        isA<NetworkException>(),
      );
      expect(mapDioException(_http(503)), isA<NetworkException>());
      expect(mapDioException(_http(429)), isA<NetworkException>());
    });

    test('401 es sesión expirada (TC-23)', () {
      expect(mapDioException(_http(401)), isA<UnauthorizedException>());
    });

    test('4xx de validación son permanentes (TC-07, TC-17, TC-18)', () {
      for (final s in [400, 403, 404, 413, 415, 422]) {
        expect(
          mapDioException(_http(s)),
          isA<PermanentException>(),
          reason: 'HTTP $s',
        );
      }
    });
  });

  test('AssignmentModel ida y vuelta', () {
    final json = {
      'id': 'asg-1',
      'activity': {
        'id': 'act-1',
        'title': 'Acreditación',
        'description': 'Entrega de credenciales',
        'dueAt': '2026-11-12T22:00:00.000Z',
        'status': 'IN_PROGRESS',
      },
      'event': {
        'id': 'evt-1',
        'name': 'Congreso universitario',
        'latitude': -21.53,
        'longitude': -64.72,
      },
    };
    final a = AssignmentModel.fromJson(json);
    expect(a.activityStatus, ActivityStatus.inProgress);
    expect(a.dueAt, DateTime.utc(2026, 11, 12, 22));
    expect(a.hasEventLocation, isTrue);
    final again = AssignmentModel.fromJson(AssignmentModel.toJson(a));
    expect(again.activityTitle, 'Acreditación');
    expect(again.eventLongitude, -64.72);
  });

  test('metadata de evidencia según §4.3.5', () {
    final e = LocalEvidence(
      clientUuid: 'uuid-1',
      assignmentId: 'asg-1',
      userId: 'u1',
      activityTitle: 't',
      eventName: 'e',
      photoPath: '/p.jpg',
      location: const GeoReading.available(
        latitude: -21.5,
        longitude: -64.7,
        accuracyM: 12.5,
      ),
      capturedAt: DateTime.utc(2026, 11, 15, 10, 30),
      notes: 'nota',
    );
    expect(EvidenceModel.toMetadataJson(e), {
      'clientUuid': 'uuid-1',
      'assignmentId': 'asg-1',
      'latitude': -21.5,
      'longitude': -64.7,
      'accuracyM': 12.5,
      'locationStatus': 'AVAILABLE',
      'capturedAt': '2026-11-15T10:30:00.000Z',
      'notes': 'nota',
    });
  });
}
