import 'package:dio/dio.dart';

import '../../core/config/app_config.dart';
import '../../core/errors/app_exception.dart';
import '../local/session_storage.dart';
import 'mock/mock_api_interceptor.dart';

/// Cliente HTTP de la API REST (§4.3.5). JSON para datos estructurados y
/// multipart/form-data para fotografías.
class ApiClient {
  ApiClient({
    required SessionStorage session,
    void Function()? onUnauthorized,
    Dio? dio,
  }) : dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: AppConfig.apiBaseUrl,
               connectTimeout: AppConfig.connectTimeout,
               receiveTimeout: AppConfig.receiveTimeout,
               sendTimeout: AppConfig.sendTimeout,
               headers: {'Accept': 'application/json'},
             ),
           ) {
    this.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await session.readToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) {
          final isLogin = error.requestOptions.path.endsWith('/auth/login');
          if (error.response?.statusCode == 401 && !isLogin) {
            onUnauthorized?.call();
          }
          handler.next(error);
        },
      ),
    );
    if (dio == null && AppConfig.useMockApi) {
      this.dio.interceptors.add(MockApiInterceptor());
    }
  }

  final Dio dio;

  /// Ejecuta la petición traduciendo errores de Dio a [AppException].
  Future<T> call<T>(Future<T> Function(Dio dio) request) async {
    try {
      return await request(dio);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}

/// Clasifica el error para decidir si la sincronización reintenta (§4.3.4
/// pasos 16 y 17). El mensaje del servidor solo se usa si viene en el campo
/// `message`; nunca se registran cabeceras ni tokens (RNF-11).
AppException mapDioException(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
      return const NetworkException(
        'El servidor tardó demasiado en responder.',
        code: 'TIMEOUT',
      );
    case DioExceptionType.connectionError:
      return const NetworkException(
        'Sin conexión con el servidor.',
        code: 'NO_CONNECTION',
      );
    case DioExceptionType.cancel:
      return const NetworkException('Envío cancelado.', code: 'CANCELLED');
    case DioExceptionType.badCertificate:
      return const PermanentException(
        'Certificado del servidor no válido.',
        code: 'BAD_CERTIFICATE',
      );
    case DioExceptionType.badResponse:
    case DioExceptionType.unknown:
      break;
  }

  final status = e.response?.statusCode;
  if (status == null) {
    return const NetworkException('Error de red.', code: 'NETWORK');
  }
  final data = e.response?.data;
  final serverMessage = data is Map && data['message'] is String
      ? data['message'] as String
      : null;

  if (status == 401) return const UnauthorizedException();
  if (status == 429) {
    // Límite de intentos (p. ej. login): se muestra el mensaje del servidor.
    return NetworkException(
      serverMessage ?? 'Demasiadas solicitudes. Espera unos minutos.',
      code: 'HTTP_429',
    );
  }
  if (status == 408 || status >= 500) {
    return NetworkException(
      'El servidor no está disponible. Se reintentará.',
      code: 'HTTP_$status',
    );
  }
  return PermanentException(
    serverMessage ??
        switch (status) {
          403 => 'No tienes permiso para esta operación.',
          404 => 'El recurso ya no existe.',
          413 => 'La fotografía supera el tamaño permitido.',
          415 => 'Formato de archivo no permitido.',
          _ => 'El servidor rechazó la solicitud.',
        },
    code: 'HTTP_$status',
  );
}
