import 'package:flutter/foundation.dart';

/// Configuración por entorno (RNF-10). Los valores se inyectan en compilación:
///
/// ```
/// flutter run --dart-define=API_BASE_URL=https://api.ejemplo.edu.bo/api/v1 \
///             --dart-define=USE_MOCK_API=false
/// ```
///
/// Nunca se guardan credenciales ni secretos en este archivo (§4.5.6).
///
/// El mismo proyecto compila para Android (app del responsable) y para Web
/// (panel administrativo, §4.3.2).
class AppConfig {
  AppConfig._();

  static const String _apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// URL base de la API REST. Por defecto, en Android `10.0.2.2` es el host
  /// del PC visto desde el emulador; en el navegador, el propio PC.
  static String get apiBaseUrl => _apiBaseUrl.isNotEmpty
      ? _apiBaseUrl
      : kIsWeb
      ? 'http://localhost:3000/api/v1'
      : 'http://10.0.2.2:3000/api/v1';

  /// Mientras el backend Node.js no esté disponible, la app puede funcionar
  /// contra un backend simulado en memoria. La interfaz lo indica como
  /// "Modo demostración" para no confundirlo con datos reales.
  ///
  /// El panel web siempre usa el backend real: el simulador solo cubre los
  /// endpoints de la app móvil.
  static bool get useMockApi => !kIsWeb && _useMockApi;
  static const bool _useMockApi = bool.fromEnvironment(
    'USE_MOCK_API',
    defaultValue: true,
  );

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration sendTimeout = Duration(seconds: 60);

  /// Tamaño máximo de fotografía aceptado antes de encolarla (el backend
  /// aplica su propio límite, TC-18).
  static const int maxPhotoBytes = 8 * 1024 * 1024;
  static const double photoMaxDimension = 1920;
  static const int photoQuality = 80;

  static const int maxNotesLength = 500;

  /// Tiempo máximo de espera de una lectura GPS.
  static const Duration gpsTimeout = Duration(seconds: 20);

  /// Por encima de esta precisión se advierte al usuario. Con "ubicación
  /// aproximada" (Android 12+) la precisión suele ser de 1 a 3 km.
  static const double lowAccuracyThresholdM = 100;

  /// Reintentos de sincronización con backoff exponencial (§4.3.4).
  static const int maxSyncRetries = 8;
  static const Duration syncBaseBackoff = Duration(seconds: 15);
  static const Duration syncMaxBackoff = Duration(minutes: 30);

  /// Política de limpieza tras confirmación del servidor (§4.3.4 paso 15).
  static const bool deleteLocalPhotoAfterSync = false;
}
