// Registro de evidencia (Pantalla C, §4.3.3, RB-06, RB-07) con los
// servicios reales de la app y plataformas simuladas.
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:eventtrack/core/network/network_monitor.dart';
import 'package:eventtrack/data/local/app_database.dart';
import 'package:eventtrack/data/local/evidence_local_data_source.dart';
import 'package:eventtrack/data/local/session_storage.dart';
import 'package:eventtrack/data/remote/api_client.dart';
import 'package:eventtrack/data/remote/remote_data_sources.dart';
import 'package:eventtrack/data/repositories/evidence_repository_impl.dart';
import 'package:eventtrack/domain/entities/assignment.dart';
import 'package:eventtrack/domain/entities/geo_reading.dart';
import 'package:eventtrack/domain/entities/local_evidence.dart';
import 'package:eventtrack/domain/entities/user.dart';
import 'package:eventtrack/features/evidence/presentation/evidence_form_controller.dart';
import 'package:eventtrack/features/evidence/services/location_service.dart';
import 'package:eventtrack/features/evidence/services/photo_service.dart';
import 'package:eventtrack/features/sync/application/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/fake_platforms.dart';

class OfflineNetwork implements NetworkMonitor {
  @override
  Future<bool> isOnline() async => false;

  @override
  Stream<bool> get onStatusChange => const Stream.empty();
}

const user = User(
  id: 'u1',
  fullName: 'Responsable de Prueba',
  email: 'r@uajms.edu.bo',
  role: UserRole.responsible,
);

final assignment = Assignment(
  id: 'asg-1',
  activityId: 'act-1',
  activityTitle: 'Acreditación',
  activityDescription: '',
  activityStatus: ActivityStatus.pending,
  dueAt: DateTime.utc(2026, 11, 20),
  eventId: 'evt-1',
  eventName: 'Congreso universitario',
  eventLatitude: -21.5337,
  eventLongitude: -64.7348,
);

void main() {
  sqfliteFfiInit();

  late Directory sandbox;
  late String docsDir;
  late String cameraFile;
  late FakeGeolocator gps;
  late FakeImagePicker picker;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('eventtrack_capture');
    docsDir = p.join(sandbox.path, 'app_flutter');
    // Foto "tomada" por la cámara en la caché del picker.
    cameraFile = p.join(sandbox.path, 'cache', 'IMG_0001.jpg');
    File(cameraFile)
      ..createSync(recursive: true)
      ..writeAsBytesSync([0xff, 0xd8, 0xff, 0xe0, ...List.filled(2048, 9)]);

    gps = FakeGeolocator();
    picker = FakeImagePicker()..nextPath = cameraFile;
    GeolocatorPlatform.instance = gps;
    ImagePickerPlatform.instance = picker;
    PathProviderPlatform.instance = FakePathProvider(docsDir);
  });

  tearDown(() => sandbox.delete(recursive: true));

  group('LocationService (geolocator)', () {
    final location = LocationService();

    test('TC-10: con permiso registra latitud, longitud y precisión', () async {
      final r = await location.getCurrentReading();
      expect(r.status, LocationStatus.available);
      expect(r.latitude, -21.5337);
      expect(r.longitude, -64.7348);
      expect(r.accuracyM, 6);
    });

    test('solicita el permiso solo cuando hace falta (RNF-04)', () async {
      await location.getCurrentReading();
      expect(gps.permissionRequests, 0);

      gps.permission = LocationPermission.denied;
      await location.getCurrentReading();
      expect(gps.permissionRequests, 1);
    });

    test('TC-11 / RB-07: permiso denegado → sin coordenadas', () async {
      gps
        ..permission = LocationPermission.denied
        ..permissionAfterRequest = LocationPermission.denied;
      final r = await location.getCurrentReading();
      expect(r.status, LocationStatus.permissionDenied);
      expect(r.latitude, isNull);
      expect(r.longitude, isNull);
      expect(r.accuracyM, isNull);
    });

    test('permiso bloqueado permanentemente', () async {
      gps.permission = LocationPermission.deniedForever;
      final r = await location.getCurrentReading();
      expect(r.status, LocationStatus.permissionDeniedForever);
      expect(gps.permissionRequests, 0);
    });

    test('GPS desactivado', () async {
      gps.serviceEnabled = false;
      expect(
        (await location.getCurrentReading()).status,
        LocationStatus.serviceDisabled,
      );
    });

    test('sin señal (timeout) → no disponible', () async {
      gps.fix = null;
      final r = await location.getCurrentReading();
      expect(r.status, LocationStatus.unavailable);
      expect(r.isAvailable, isFalse);
    });

    test('precisión 0 no se registra como dato válido', () async {
      gps.fix = (lat: 1, lng: 2, accuracy: 0);
      expect((await location.getCurrentReading()).accuracyM, isNull);
    });
  });

  group('PhotoService (image_picker + almacenamiento privado)', () {
    final photos = PhotoService();

    test('pide la foto comprimida y sin metadatos completos', () async {
      await photos.pick(PhotoSource.camera);
      expect(picker.lastSource, ImageSource.camera);
      expect(picker.lastOptions!.maxWidth, 1920);
      expect(picker.lastOptions!.imageQuality, 80);
      expect(picker.lastOptions!.requestFullMetadata, isFalse);
    });

    test('cancelar la cámara devuelve null', () async {
      picker.nextPath = null;
      expect(await photos.pick(PhotoSource.camera), isNull);
    });

    test('TC-09: cámara denegada → PhotoPermissionDeniedException', () async {
      picker.denyAccess = true;
      await expectLater(
        photos.pick(PhotoSource.camera),
        throwsA(
          isA<PhotoPermissionDeniedException>().having(
            (e) => e.source,
            'source',
            PhotoSource.camera,
          ),
        ),
      );
    });

    test('copia la foto al directorio privado con el client_uuid', () async {
      final picked = await photos.pick(PhotoSource.camera);
      final stored = await photos.persist(picked!, 'uuid-123');
      expect(stored, p.join(docsDir, 'evidences', 'uuid-123.jpg'));
      expect(
        File(stored).readAsBytesSync(),
        File(cameraFile).readAsBytesSync(),
      );
    });

    test('rechaza fotos sobre el límite antes de encolarlas', () async {
      File(cameraFile).writeAsBytesSync(List.filled(8 * 1024 * 1024 + 1, 0));
      final picked = await photos.pick(PhotoSource.camera);
      await expectLater(
        photos.persist(picked!, 'uuid-big'),
        throwsA(isA<PhotoTooLargeException>()),
      );
    });
  });

  group('EvidenceFormController (CU-07)', () {
    late AppDatabase db;
    late SyncService sync;
    late EvidenceRepositoryImpl repo;

    setUp(() async {
      db = await AppDatabase.open(
        factory: databaseFactoryFfiNoIsolate,
        path: inMemoryDatabasePath,
      );
      repo = EvidenceRepositoryImpl(
        EvidenceLocalDataSource(db),
        RemoteDataSource(ApiClient(session: SessionStorage(), dio: Dio())),
      );
      sync = SyncService(
        repository: repo,
        network: OfflineNetwork(),
        store: db,
      );
      await sync.start(user.id);
    });

    tearDown(() async {
      sync.dispose();
      await db.close();
    });

    EvidenceFormController controller() => EvidenceFormController(
      assignment: assignment,
      user: user,
      photos: PhotoService(),
      location: LocationService(),
      repository: repo,
      sync: sync,
    );

    test('foto + GPS automático + guardado offline como PENDING', () async {
      final c = controller();
      await c.pickPhoto(PhotoSource.camera);
      expect(c.photo, isNotNull);
      expect(c.capturedAt, isNotNull);
      // La ubicación se pide al capturar la foto.
      expect(c.reading!.isAvailable, isTrue);
      expect(c.distanceToEventM, 0);
      expect(c.hasUnsavedData, isTrue);

      c.notes = '  Ambiente listo  ';
      final result = await c.save();
      expect(result.outcome, SaveOutcome.pending);
      expect(c.hasUnsavedData, isFalse);

      final rows = await db.db.query(AppDatabase.evidencesTable);
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row['client_uuid'], c.clientUuid);
      expect(row['assignment_id'], 'asg-1');
      expect(row['latitude'], -21.5337);
      expect(row['longitude'], -64.7348);
      expect(row['accuracy_m'], 6);
      expect(row['notes'], 'Ambiente listo');
      expect(row['sync_status'], SyncStatus.pending.code);
      expect(DateTime.parse(row['captured_at']! as String).isUtc, isTrue);

      // Solo la ruta local, nunca Base64 (§4.3.3).
      final path = row['photo_path']! as String;
      expect(path, p.join(docsDir, 'evidences', '${c.clientUuid}.jpg'));
      expect(File(path).existsSync(), isTrue);
      for (final value in row.values) {
        if (value is String) expect(value.length, lessThan(600));
      }
    });

    test(
      'RB-07: GPS denegado → se guarda con ubicación no disponible',
      () async {
        gps
          ..permission = LocationPermission.denied
          ..permissionAfterRequest = LocationPermission.denied;
        final c = controller();
        await c.pickPhoto(PhotoSource.camera);
        expect(c.reading!.status, LocationStatus.permissionDenied);

        await c.save();
        final row = (await db.db.query(AppDatabase.evidencesTable)).single;
        expect(row['latitude'], isNull);
        expect(row['longitude'], isNull);
        expect(row['accuracy_m'], isNull);
        expect(row['location_status'], 'PERMISSION_DENIED');
      },
    );

    test('TC-09: cámara denegada → aviso claro y sin foto', () async {
      picker.denyAccess = true;
      final c = controller();
      await c.pickPhoto(PhotoSource.camera);
      expect(c.photo, isNull);
      expect(c.photoError, contains('Permiso de cámara denegado'));
      expect(c.hasUnsavedData, isFalse);
    });

    test('ubicación aproximada → advertencia de precisión baja', () async {
      gps.fix = (lat: -21.53, lng: -64.73, accuracy: 1800);
      final c = controller();
      await c.requestLocation();
      expect(c.reading!.isAvailable, isTrue);
      expect(c.lowAccuracy, isTrue);
    });

    test('TC-22: la evidencia sobrevive al cierre de la app', () async {
      final c = controller();
      await c.pickPhoto(PhotoSource.camera);
      await c.save();
      sync.dispose();

      // "Reabrir" la app: nueva instancia de la cola sobre la misma base.
      sync = SyncService(
        repository: repo,
        network: OfflineNetwork(),
        store: db,
      );
      await sync.start(user.id);
      expect(sync.evidences.single.clientUuid, c.clientUuid);
      expect(File(sync.evidences.single.photoPath).existsSync(), isTrue);
    });
  });
}
