import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'domain/repositories/repositories.dart';
import 'features/activities/presentation/activities_controller.dart';
import 'features/auth/presentation/auth_controller.dart';
import 'features/evidence/services/location_service.dart';
import 'features/evidence/services/photo_service.dart';
import 'features/sync/application/sync_service.dart';

class EventTrackApp extends StatefulWidget {
  const EventTrackApp({
    super.key,
    required this.auth,
    required this.activities,
    required this.sync,
    required this.evidenceRepository,
    required this.photos,
    required this.location,
  });

  final AuthController auth;
  final ActivitiesController activities;
  final SyncService sync;
  final EvidenceRepository evidenceRepository;
  final PhotoService photos;
  final LocationService location;

  @override
  State<EventTrackApp> createState() => _EventTrackAppState();
}

class _EventTrackAppState extends State<EventTrackApp> {
  late final GoRouter _router = buildRouter(widget.auth);

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.auth),
        ChangeNotifierProvider.value(value: widget.activities),
        ChangeNotifierProvider.value(value: widget.sync),
        Provider.value(value: widget.evidenceRepository),
        Provider.value(value: widget.photos),
        Provider.value(value: widget.location),
      ],
      child: MaterialApp.router(
        title: 'EventTrack',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        routerConfig: _router,
      ),
    );
  }
}
