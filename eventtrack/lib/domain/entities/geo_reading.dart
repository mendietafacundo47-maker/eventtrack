/// Resultado de intentar obtener la ubicación. Si no hay lectura válida, las
/// coordenadas quedan en `null` y el estado explica el motivo: nunca se
/// inventan coordenadas (RB-07, TC-11).
enum LocationStatus {
  available('AVAILABLE', 'Ubicación obtenida'),
  permissionDenied('PERMISSION_DENIED', 'Permiso de ubicación denegado'),
  permissionDeniedForever(
    'PERMISSION_DENIED_FOREVER',
    'Permiso de ubicación bloqueado',
  ),
  serviceDisabled('SERVICE_DISABLED', 'GPS desactivado'),
  unavailable('UNAVAILABLE', 'Ubicación no disponible');

  const LocationStatus(this.code, this.label);

  final String code;
  final String label;

  static LocationStatus fromCode(String? code) =>
      LocationStatus.values.firstWhere(
        (s) => s.code == code,
        orElse: () => LocationStatus.unavailable,
      );
}

class GeoReading {
  const GeoReading._({
    required this.status,
    this.latitude,
    this.longitude,
    this.accuracyM,
  });

  const GeoReading.available({
    required double latitude,
    required double longitude,
    double? accuracyM,
  }) : this._(
         status: LocationStatus.available,
         latitude: latitude,
         longitude: longitude,
         accuracyM: accuracyM,
       );

  const GeoReading.missing(LocationStatus status)
    : assert(status != LocationStatus.available),
      latitude = null,
      longitude = null,
      accuracyM = null,
      status = status;

  final LocationStatus status;
  final double? latitude;
  final double? longitude;

  /// Precisión estimada en metros reportada por el dispositivo.
  final double? accuracyM;

  bool get isAvailable =>
      status == LocationStatus.available &&
      latitude != null &&
      longitude != null;
}
