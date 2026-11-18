import 'dart:async';

import 'package:flutter/material.dart';

import '../data/local/session_storage.dart';
import '../data/remote/api_client.dart';
import '../data/remote/panel_api.dart';
import '../data/remote/remote_data_sources.dart';
import '../data/repositories/auth_repository_impl.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/panel/presentation/panel_app.dart';

/// Web: panel administrativo para organizadores, supervisores y
/// administradores. No usa SQLite ni cola offline (solo Android).
Future<void> bootstrap() async {
  final session = SessionStorage();

  late final AuthController auth;
  final api = ApiClient(
    session: session,
    onUnauthorized: () => unawaited(auth.onSessionExpired()),
  );
  auth = AuthController(AuthRepositoryImpl(RemoteDataSource(api), session));

  runApp(PanelApp(auth: auth, api: PanelApi(api)));

  await auth.restore();
}
