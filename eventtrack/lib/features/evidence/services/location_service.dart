import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../../../core/config/app_config.dart';
import '../../../domain/entities/geo_reading.dart';

/// Lectura GPS puntual al registrar evidencia. No hay rastreo en segundo
/// plano (§3.2.3, §4.3.1). Si no se obtiene una lectura válida devuelve un
/// [GeoReading.missing] con el motivo; nunca coordenadas inventadas (RB-07).
class LocationService {
  Future<GeoReading> getCurrentReading() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const GeoReading.missing(LocationStatus.serviceDisabled);
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      return const GeoReading.missing(LocationStatus.permissionDenied);
    }
    if (permission == LocationPermission.deniedForever) {
      return const GeoReading.missing(LocationStatus.permissionDeniedForever);
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: AppConfig.gpsTimeout,
        ),
      );
      if (position.latitude.abs() > 90 || position.longitude.abs() > 180) {
        return const GeoReading.missing(LocationStatus.unavailable);
      }
      return GeoReading.available(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyM: position.accuracy > 0 ? position.accuracy : null,
      );
    } on TimeoutException {
      return const GeoReading.missing(LocationStatus.unavailable);
    } on LocationServiceDisabledException {
      return const GeoReading.missing(LocationStatus.serviceDisabled);
    } on PermissionDeniedException {
      return const GeoReading.missing(LocationStatus.permissionDenied);
    }
  }

  /// Distancia al punto del evento, solo como indicador de consistencia
  /// (RB-11).
  double distanceMeters(double lat1, double lng1, double lat2, double lng2) =>
      Geolocator.distanceBetween(lat1, lng1, lat2, lng2);

  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  Future<bool> openAppSettings() => Geolocator.openAppSettings();
}
