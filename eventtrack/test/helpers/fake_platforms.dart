import 'dart:async';

import 'package:flutter/services.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// GPS simulado: permite probar LocationService sin dispositivo.
class FakeGeolocator extends GeolocatorPlatform
    with MockPlatformInterfaceMixin {
  bool serviceEnabled = true;
  LocationPermission permission = LocationPermission.whileInUse;

  /// Resultado de `requestPermission` cuando el permiso estaba `denied`.
  LocationPermission permissionAfterRequest = LocationPermission.whileInUse;
  int permissionRequests = 0;

  /// `null` simula un timeout de lectura.
  ({double lat, double lng, double accuracy})? fix = (
    lat: -21.5337,
    lng: -64.7348,
    accuracy: 6,
  );

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    permissionRequests++;
    permission = permissionAfterRequest;
    return permission;
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    final f = fix;
    if (f == null) {
      throw TimeoutException('sin señal', locationSettings?.timeLimit);
    }
    return Position(
      latitude: f.lat,
      longitude: f.lng,
      accuracy: f.accuracy,
      timestamp: DateTime.now(),
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }
}

/// Cámara/galería simulada.
class FakeImagePicker extends ImagePickerPlatform
    with MockPlatformInterfaceMixin {
  /// Ruta del archivo que "devuelve" la cámara; `null` = usuario canceló.
  String? nextPath;
  bool denyAccess = false;
  ImagePickerOptions? lastOptions;
  ImageSource? lastSource;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    lastSource = source;
    lastOptions = options;
    if (denyAccess) {
      throw PlatformException(
        code: source == ImageSource.camera
            ? 'camera_access_denied'
            : 'photo_access_denied',
      );
    }
    return nextPath == null ? null : XFile(nextPath!);
  }

  @override
  Future<LostDataResponse> getLostData() async => LostDataResponse.empty();
}

/// Directorio privado de la app simulado.
class FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  FakePathProvider(this.documentsPath);

  final String documentsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}
