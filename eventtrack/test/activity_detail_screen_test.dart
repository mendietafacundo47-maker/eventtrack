// Pantalla C: advertencias visibles de permisos (§3.2.3, §4.3.6).
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:eventtrack/core/theme/app_theme.dart';
import 'package:eventtrack/data/local/app_database.dart';
import 'package:eventtrack/data/local/evidence_local_data_source.dart';
import 'package:eventtrack/data/local/session_storage.dart';
import 'package:eventtrack/data/remote/api_client.dart';
import 'package:eventtrack/data/remote/remote_data_sources.dart';
import 'package:eventtrack/data/repositories/evidence_repository_impl.dart';
import 'package:eventtrack/domain/entities/user.dart';
import 'package:eventtrack/domain/repositories/repositories.dart';
import 'package:eventtrack/features/auth/presentation/auth_controller.dart';
import 'package:eventtrack/features/evidence/presentation/activity_detail_screen.dart';
import 'package:eventtrack/features/evidence/presentation/evidence_form_controller.dart';
import 'package:eventtrack/features/evidence/services/location_service.dart';
import 'package:eventtrack/features/evidence/services/photo_service.dart';
import 'package:eventtrack/features/sync/application/sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'evidence_capture_test.dart' show OfflineNetwork, assignment, user;
import 'helpers/fake_platforms.dart';

class FakeAuthRepository implements AuthRepository {
  @override
  Future<User> login({required String email, required String password}) async =>
      user;

  @override
  Future<User?> restoreSession() async => user;

  @override
  Future<void> logout() async {}
}

void main() {
  sqfliteFfiInit();
  WidgetController.hitTestWarningShouldBeFatal = true;

  late FakeGeolocator gps;
  late FakeImagePicker picker;
  late AppDatabase db;
  late SyncService sync;
  late AuthController auth;
  late EvidenceRepositoryImpl repo;

  setUp(() async {
    gps = FakeGeolocator();
    picker = FakeImagePicker();
    GeolocatorPlatform.instance = gps;
    ImagePickerPlatform.instance = picker;
    PathProviderPlatform.instance = FakePathProvider(Directory.systemTemp.path);
  });

  Future<void> tapAfterScroll(WidgetTester tester, String text) async {
    await tester.scrollUntilVisible(
      find.text(text),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text(text));
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    // Pantalla de teléfono: 360 × 800 dp.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
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
      auth = AuthController(FakeAuthRepository(), sync);
      await auth.restore();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider.value(value: sync),
          ChangeNotifierProvider(
            create: (_) => EvidenceFormController(
              assignment: assignment,
              user: user,
              photos: PhotoService(),
              location: LocationService(),
              repository: repo,
              sync: sync,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ActivityDetailScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  tearDown(() async {
    sync.dispose();
    await db.close();
  });

  testWidgets('muestra los datos de la actividad y el responsable', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(find.text('Acreditación'), findsOneWidget);
    expect(find.text('Congreso universitario'), findsOneWidget);
    expect(find.text('Responsable de Prueba'), findsOneWidget);
    expect(find.text('TOMAR / ADJUNTAR FOTO'), findsOneWidget);
    expect(find.text('GUARDAR EVIDENCIA'), findsOneWidget);
  });

  testWidgets('GPS bloqueado: advertencia y acceso a ajustes', (tester) async {
    gps.permission = LocationPermission.deniedForever;
    await pumpScreen(tester);

    await tapAfterScroll(tester, 'Obtener ahora');

    expect(find.text('Permiso de ubicación bloqueado'), findsOneWidget);
    expect(find.textContaining('Ajustes > Aplicaciones'), findsOneWidget);
    expect(find.text('Abrir ajustes'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('GPS desactivado: pide activarlo', (tester) async {
    gps.serviceEnabled = false;
    await pumpScreen(tester);

    await tapAfterScroll(tester, 'Obtener ahora');

    expect(find.text('GPS desactivado'), findsOneWidget);
    expect(find.textContaining('Activa la ubicación'), findsOneWidget);
  });

  testWidgets('cámara denegada: advertencia con opción de reintentar', (
    tester,
  ) async {
    picker.denyAccess = true;
    await pumpScreen(tester);

    await tester.tap(find.text('TOMAR / ADJUNTAR FOTO'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tomar foto con la cámara'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Permiso de cámara denegado'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Reintentar'), findsOneWidget);
  });

  testWidgets('guardar sin foto muestra un aviso', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('GUARDAR EVIDENCIA'));
    await tester.pump();
    expect(
      find.text('Agrega una fotografía antes de guardar.'),
      findsOneWidget,
    );
  });
}
