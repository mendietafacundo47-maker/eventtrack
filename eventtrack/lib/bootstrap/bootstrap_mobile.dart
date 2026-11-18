import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../core/network/network_monitor.dart';
import '../data/local/app_database.dart';
import '../data/local/assignment_cache.dart';
import '../data/local/evidence_local_data_source.dart';
import '../data/local/session_storage.dart';
import '../data/remote/api_client.dart';
import '../data/remote/remote_data_sources.dart';
import '../data/repositories/assignment_repository_impl.dart';
import '../data/repositories/auth_repository_impl.dart';
import '../data/repositories/evidence_repository_impl.dart';
import '../features/activities/presentation/activities_controller.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/evidence/services/location_service.dart';
import '../features/evidence/services/photo_service.dart';
import '../features/sync/application/sync_service.dart';

/// Android: app del responsable con SQLite, cámara, GPS y cola offline.
Future<void> bootstrap() async {
  final database = await AppDatabase.open();
  final session = SessionStorage();

  late final AuthController auth;
  final api = ApiClient(
    session: session,
    onUnauthorized: () => unawaited(auth.onSessionExpired()),
  );
  final remote = RemoteDataSource(api);

  final evidenceRepository = EvidenceRepositoryImpl(
    EvidenceLocalDataSource(database),
    remote,
  );
  final sync = SyncService(
    repository: evidenceRepository,
    network: ConnectivityNetworkMonitor(),
    store: database,
  );
  auth = AuthController(AuthRepositoryImpl(remote, session), sync);

  final activities = ActivitiesController(
    AssignmentRepositoryImpl(remote, AssignmentCache(database)),
  );
  auth.addListener(() => activities.bindUser(auth.user?.id));

  runApp(
    EventTrackApp(
      auth: auth,
      activities: activities,
      sync: sync,
      evidenceRepository: evidenceRepository,
      photos: PhotoService(),
      location: LocationService(),
    ),
  );

  await auth.restore();
}
