import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/config/app_config.dart';

enum PhotoSource { camera, gallery }

class PhotoPermissionDeniedException implements Exception {
  const PhotoPermissionDeniedException(this.source);

  final PhotoSource source;
}

class PhotoTooLargeException implements Exception {
  const PhotoTooLargeException(this.bytes);

  final int bytes;
}

/// Captura o selección de la fotografía de evidencia (RF-09).
///
/// La imagen se comprime y se copia al almacenamiento privado de la app con
/// el `client_uuid` como nombre, para que sobreviva a la limpieza de la
/// caché del picker hasta su sincronización (§4.3.3).
class PhotoService {
  PhotoService([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Devuelve `null` si el usuario canceló.
  Future<XFile?> pick(PhotoSource source) async {
    try {
      return await _picker.pickImage(
        source: source == PhotoSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        maxWidth: AppConfig.photoMaxDimension,
        maxHeight: AppConfig.photoMaxDimension,
        imageQuality: AppConfig.photoQuality,
        requestFullMetadata: false,
      );
    } on PlatformException catch (e) {
      if (e.code.contains('access_denied')) {
        throw PhotoPermissionDeniedException(source);
      }
      rethrow;
    }
  }

  /// Android puede destruir la actividad mientras la cámara está abierta;
  /// esto recupera la foto tomada en ese caso.
  Future<XFile?> retrieveLost() async {
    if (!Platform.isAndroid) return null;
    final response = await _picker.retrieveLostData();
    if (response.isEmpty) return null;
    return response.file;
  }

  /// Copia la foto al directorio privado `evidences/` y devuelve su ruta.
  Future<String> persist(XFile photo, String clientUuid) async {
    final size = await photo.length();
    if (size > AppConfig.maxPhotoBytes) throw PhotoTooLargeException(size);

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'evidences'));
    await dir.create(recursive: true);

    var ext = p.extension(photo.path).toLowerCase();
    if (!const {'.jpg', '.jpeg', '.png', '.webp'}.contains(ext)) ext = '.jpg';
    final target = p.join(dir.path, '$clientUuid$ext');
    await photo.saveTo(target);
    return target;
  }
}
