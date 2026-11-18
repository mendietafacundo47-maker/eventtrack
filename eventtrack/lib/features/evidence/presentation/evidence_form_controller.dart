import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/app_config.dart';
import '../../../domain/entities/assignment.dart';
import '../../../domain/entities/geo_reading.dart';
import '../../../domain/entities/local_evidence.dart';
import '../../../domain/entities/user.dart';
import '../../../domain/repositories/repositories.dart';
import '../../sync/application/sync_service.dart';
import '../services/location_service.dart';
import '../services/photo_service.dart';

enum SaveOutcome { synced, pending, failed }

class SaveResult {
  const SaveResult(this.outcome, this.message);

  final SaveOutcome outcome;
  final String message;
}

/// Flujo principal de CU-07 "Registrar evidencia de actividad" (§4.2.2).
class EvidenceFormController extends ChangeNotifier {
  EvidenceFormController({
    required this.assignment,
    required this.user,
    required this._photos,
    required this._location,
    required this._repository,
    required this._sync,
  }) : // UUID generado al crear el registro: clave de idempotencia (RB-10).
       clientUuid = const Uuid().v4();

  final Assignment assignment;
  final User user;
  final PhotoService _photos;
  final LocationService _location;
  final EvidenceRepository _repository;
  final SyncService _sync;
  final String clientUuid;

  XFile? _photo;
  DateTime? _capturedAt;
  GeoReading? _reading;
  bool _locating = false;
  bool _saving = false;
  bool _saved = false;
  String? _photoError;
  String notes = '';

  XFile? get photo => _photo;
  DateTime? get capturedAt => _capturedAt;
  GeoReading? get reading => _reading;
  bool get locating => _locating;
  bool get saving => _saving;
  String? get photoError => _photoError;

  /// Hay datos que se perderían al salir (confirmación, §4.3.6).
  bool get hasUnsavedData => !_saved && _photo != null;

  /// La lectura existe pero es poco precisa (p. ej. permiso "aproximado").
  bool get lowAccuracy {
    final accuracy = _reading?.accuracyM;
    return _reading?.isAvailable == true &&
        accuracy != null &&
        accuracy > AppConfig.lowAccuracyThresholdM;
  }

  Future<bool> openAppSettings() => _location.openAppSettings();

  /// Indicador de consistencia respecto al punto del evento (RB-11).
  double? get distanceToEventM {
    final r = _reading;
    if (r == null || !r.isAvailable || !assignment.hasEventLocation) {
      return null;
    }
    return _location.distanceMeters(
      r.latitude!,
      r.longitude!,
      assignment.eventLatitude!,
      assignment.eventLongitude!,
    );
  }

  Future<void> recoverLostPhoto() async {
    final lost = await _photos.retrieveLost();
    if (lost != null) await _setPhoto(lost);
  }

  Future<void> pickPhoto(PhotoSource source) async {
    _photoError = null;
    notifyListeners();
    try {
      final picked = await _photos.pick(source);
      if (picked == null) return; // Cancelado por el usuario.
      await _setPhoto(picked);
    } on PhotoPermissionDeniedException catch (e) {
      // Flujo alternativo C: permitir reintentar o cancelar.
      _photoError = e.source == PhotoSource.camera
          ? 'Permiso de cámara denegado. Habilítalo en Ajustes > Aplicaciones '
                '> EventTrack > Permisos, o adjunta una foto de la galería.'
          : 'Permiso de fotos denegado. Habilítalo en los ajustes de la app.';
      notifyListeners();
    } catch (e) {
      _photoError = 'No se pudo obtener la fotografía. Intenta nuevamente.';
      notifyListeners();
    }
  }

  Future<void> _setPhoto(XFile photo) async {
    _photo = photo;
    _capturedAt = DateTime.now().toUtc();
    notifyListeners();
    // La ubicación se solicita al registrar la evidencia (§3.2.3).
    if (_reading == null || !_reading!.isAvailable) await requestLocation();
  }

  Future<void> requestLocation() async {
    if (_locating) return;
    _locating = true;
    notifyListeners();
    try {
      _reading = await _location.getCurrentReading();
    } catch (_) {
      _reading = const GeoReading.missing(LocationStatus.unavailable);
    } finally {
      _locating = false;
      notifyListeners();
    }
  }

  Future<bool> openSettingsFor(LocationStatus status) =>
      status == LocationStatus.serviceDisabled
      ? _location.openLocationSettings()
      : _location.openAppSettings();

  /// Valida, guarda localmente (PENDING) y luego intenta sincronizar.
  Future<SaveResult> save() async {
    final photo = _photo;
    if (photo == null) {
      throw StateError('Se requiere una fotografía.');
    }
    _saving = true;
    notifyListeners();

    String? storedPath;
    try {
      storedPath = await _photos.persist(photo, clientUuid);
      await _repository.saveLocal(
        LocalEvidence(
          clientUuid: clientUuid,
          assignmentId: assignment.id,
          userId: user.id,
          activityTitle: assignment.activityTitle,
          eventName: assignment.eventName,
          photoPath: storedPath,
          location:
              _reading ?? const GeoReading.missing(LocationStatus.unavailable),
          capturedAt: _capturedAt ?? DateTime.now().toUtc(),
          notes: notes.trim().length > AppConfig.maxNotesLength
              ? notes.trim().substring(0, AppConfig.maxNotesLength)
              : notes.trim(),
        ),
      );
      _saved = true;
    } on PhotoTooLargeException {
      _saving = false;
      notifyListeners();
      return const SaveResult(
        SaveOutcome.failed,
        'La fotografía es demasiado grande. Toma otra con menor resolución.',
      );
    } catch (e) {
      if (storedPath != null) {
        final f = File(storedPath);
        if (await f.exists()) await f.delete();
      }
      _saving = false;
      notifyListeners();
      return const SaveResult(
        SaveOutcome.failed,
        'No se pudo guardar la evidencia en el dispositivo.',
      );
    }

    // Ya está a salvo localmente; el envío no bloquea el resultado.
    await _sync.refresh();
    await _sync.syncNow();
    final status = _sync.findByUuid(clientUuid)?.syncStatus;
    _saving = false;
    notifyListeners();

    return switch (status) {
      SyncStatus.synced => const SaveResult(
        SaveOutcome.synced,
        'Evidencia guardada y sincronizada.',
      ),
      SyncStatus.failed => SaveResult(
        SaveOutcome.failed,
        'Evidencia guardada, pero el servidor la rechazó: '
        '${_sync.findByUuid(clientUuid)?.lastError ?? ''}',
      ),
      _ => const SaveResult(
        SaveOutcome.pending,
        'Evidencia guardada en el dispositivo. Se sincronizará al recuperar la conexión.',
      ),
    };
  }
}
