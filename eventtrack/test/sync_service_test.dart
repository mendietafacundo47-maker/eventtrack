import 'dart:async';

import 'package:dio/dio.dart';
import 'package:eventtrack/core/errors/app_exception.dart';
import 'package:eventtrack/core/network/network_monitor.dart';
import 'package:eventtrack/data/local/app_database.dart';
import 'package:eventtrack/data/local/evidence_local_data_source.dart';
import 'package:eventtrack/data/local/session_storage.dart';
import 'package:eventtrack/data/remote/api_client.dart';
import 'package:eventtrack/data/remote/remote_data_sources.dart';
import 'package:eventtrack/data/repositories/evidence_repository_impl.dart';
import 'package:eventtrack/domain/entities/geo_reading.dart';
import 'package:eventtrack/domain/entities/local_evidence.dart';
import 'package:eventtrack/features/sync/application/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeNetwork implements NetworkMonitor {
  bool online = true;
  final _controller = StreamController<bool>.broadcast();

  void set(bool value) {
    online = value;
    _controller.add(value);
  }

  @override
  Future<bool> isOnline() async => online;

  @override
  Stream<bool> get onStatusChange => _controller.stream;
}

/// Repositorio real (SQLite) con el envío HTTP reemplazado por un fake.
class TestEvidenceRepository extends EvidenceRepositoryImpl {
  TestEvidenceRepository(EvidenceLocalDataSource local)
    : super(
        local,
        RemoteDataSource(ApiClient(session: SessionStorage(), dio: Dio())),
      );

  /// Simula el servidor: idempotente por client_uuid (RB-10).
  final Map<String, EvidenceReceipt> server = {};
  final List<String> uploadCalls = [];
  Exception? nextError;

  @override
  Future<EvidenceReceipt> upload(LocalEvidence evidence) async {
    uploadCalls.add(evidence.clientUuid);
    final error = nextError;
    if (error != null) throw error;
    return server.putIfAbsent(
      evidence.clientUuid,
      () => EvidenceReceipt(
        evidenceId: 'srv-${server.length + 1}',
        status: 'PENDING_REVIEW',
        receivedAt: DateTime.utc(2026, 11, 15, 12),
      ),
    );
  }
}

LocalEvidence evidence(
  String uuid, {
  double? lat = -21.53,
  double? lng = -64.73,
}) => LocalEvidence(
  clientUuid: uuid,
  assignmentId: 'asg-1',
  userId: 'u1',
  activityTitle: 'Inspección de Zona A',
  eventName: 'Evento Central',
  photoPath: '/tmp/$uuid.jpg',
  location: lat == null
      ? const GeoReading.missing(LocationStatus.permissionDenied)
      : GeoReading.available(latitude: lat, longitude: lng!, accuracyM: 8),
  capturedAt: DateTime.utc(2026, 11, 15, 10),
  notes: 'ok',
);

void main() {
  sqfliteFfiInit();

  late AppDatabase db;
  late EvidenceLocalDataSource local;
  late TestEvidenceRepository repo;
  late FakeNetwork network;
  late SyncService sync;
  late DateTime now;

  Future<void> settle() async {
    while (sync.isSyncing) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  setUp(() async {
    db = await AppDatabase.open(
      factory: databaseFactoryFfiNoIsolate,
      path: inMemoryDatabasePath,
    );
    local = EvidenceLocalDataSource(db);
    repo = TestEvidenceRepository(local);
    network = FakeNetwork();
    now = DateTime.utc(2026, 11, 15, 12);
    sync = SyncService(
      repository: repo,
      network: network,
      store: db,
      clock: () => now,
      maxRetries: 3,
      baseBackoff: const Duration(seconds: 10),
      maxBackoff: const Duration(minutes: 1),
    );
  });

  tearDown(() async {
    sync.dispose();
    await db.close();
  });

  test(
    'TC-13: sin conexión la evidencia queda PENDING y no se envía',
    () async {
      network.online = false;
      await repo.saveLocal(evidence('a'));
      await sync.start('u1');
      await settle();

      expect(repo.uploadCalls, isEmpty);
      expect(sync.evidences.single.syncStatus, SyncStatus.pending);
      expect(sync.pendingCount, 1);
    },
  );

  test(
    'TC-14: al recuperar la conexión se sincroniza y marca SYNCED',
    () async {
      network.online = false;
      await repo.saveLocal(evidence('a'));
      await sync.start('u1');
      await settle();

      network.set(true);
      await Future<void>.delayed(Duration.zero);
      await settle();

      final e = sync.evidences.single;
      expect(e.syncStatus, SyncStatus.synced);
      expect(e.serverEvidenceId, 'srv-1');
      expect(e.serverReceivedAt, DateTime.utc(2026, 11, 15, 12));
      expect(sync.lastSyncAt, now);
    },
  );

  test('TC-15: reenviar el mismo UUID no crea duplicados', () async {
    await repo.saveLocal(evidence('a'));
    await sync.start('u1');
    await settle();

    // Simula un reenvío (p. ej. respuesta perdida tras guardar en servidor).
    final id = sync.evidences.single.localId!;
    await repo.resetForRetry(id);
    await sync.syncNow(ignoreBackoff: true);

    expect(repo.uploadCalls, ['a', 'a']);
    expect(repo.server, hasLength(1));
    expect(sync.evidences.single.serverEvidenceId, 'srv-1');
  });

  test('RB-10: el client_uuid es único también en la base local', () async {
    await repo.saveLocal(evidence('a'));
    expect(
      () => repo.saveLocal(evidence('a')),
      throwsA(isA<DatabaseException>()),
    );
  });

  test(
    'TC-16: error de servidor conserva la evidencia y programa backoff',
    () async {
      repo.nextError = const NetworkException('caído', code: 'HTTP_503');
      await repo.saveLocal(evidence('a'));
      await sync.start('u1');
      await settle();

      final e = sync.evidences.single;
      expect(e.syncStatus, SyncStatus.pending);
      expect(e.retryCount, 1);
      expect(e.nextRetryAt, now.add(const Duration(seconds: 10)));
      expect(e.lastError, contains('HTTP_503'));

      // Antes del backoff no se reintenta automáticamente.
      await sync.syncNow();
      expect(repo.uploadCalls, hasLength(1));

      // Vencido el backoff y con el servidor disponible, se sincroniza.
      repo.nextError = null;
      now = now.add(const Duration(seconds: 11));
      await sync.syncNow();
      expect(sync.evidences.single.syncStatus, SyncStatus.synced);
    },
  );

  test('tras el límite de reintentos la evidencia pasa a FAILED', () async {
    repo.nextError = const NetworkException('timeout', code: 'TIMEOUT');
    await repo.saveLocal(evidence('a'));
    await sync.start('u1');
    await settle();
    for (var i = 0; i < 3; i++) {
      await sync.syncNow(ignoreBackoff: true);
    }
    final e = sync.evidences.single;
    expect(e.syncStatus, SyncStatus.failed);
    expect(repo.uploadCalls, hasLength(3));
  });

  test('error permanente pasa a FAILED sin reintento automático', () async {
    repo.nextError = const PermanentException(
      'Asignación inexistente',
      code: 'HTTP_404',
    );
    await repo.saveLocal(evidence('a'));
    await sync.start('u1');
    await settle();

    expect(sync.evidences.single.syncStatus, SyncStatus.failed);
    await sync.syncNow(ignoreBackoff: true);
    expect(repo.uploadCalls, hasLength(1));

    // Reintento manual desde la pantalla D.
    repo.nextError = null;
    await sync.retry(sync.evidences.single);
    expect(sync.evidences.single.syncStatus, SyncStatus.synced);
  });

  test(
    '401 conserva la evidencia como PENDING sin consumir intentos',
    () async {
      repo.nextError = const UnauthorizedException();
      await repo.saveLocal(evidence('a'));
      await sync.start('u1');
      await settle();

      final e = sync.evidences.single;
      expect(e.syncStatus, SyncStatus.pending);
      expect(e.retryCount, 0);
    },
  );

  test(
    'TC-22: un envío interrumpido (UPLOADING) se recupera al iniciar',
    () async {
      final saved = await repo.saveLocal(evidence('a'));
      await repo.markUploading(saved.localId!);
      network.online = false;

      await sync.start('u1');
      await settle();

      expect(sync.evidences.single.syncStatus, SyncStatus.pending);
    },
  );

  test(
    'RB-07: sin GPS se guarda como no disponible, sin coordenadas',
    () async {
      await repo.saveLocal(evidence('a', lat: null, lng: null));
      final e = (await repo.getAll('u1')).single;
      expect(e.location.latitude, isNull);
      expect(e.location.longitude, isNull);
      expect(e.location.status, LocationStatus.permissionDenied);
    },
  );

  test('TC-12: coordenadas fuera de rango son rechazadas localmente', () async {
    expect(
      () => repo.saveLocal(evidence('a', lat: 120, lng: 200)),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('backoff exponencial acotado', () {
    expect(sync.backoffFor(1), const Duration(seconds: 10));
    expect(sync.backoffFor(2), const Duration(seconds: 20));
    expect(sync.backoffFor(3), const Duration(seconds: 40));
    expect(sync.backoffFor(4), const Duration(minutes: 1));
    expect(sync.backoffFor(10), const Duration(minutes: 1));
  });

  test('solo se procesan evidencias del usuario autenticado', () async {
    await repo.saveLocal(evidence('a'));
    await sync.start('otro-usuario');
    await settle();
    expect(repo.uploadCalls, isEmpty);
    expect(sync.evidences, isEmpty);
  });
}
