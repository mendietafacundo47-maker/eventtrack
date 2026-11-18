/// Errores de la aplicación clasificados según cómo debe reaccionar la cola
/// de sincronización (§4.3.4): los transitorios se reintentan con backoff,
/// los permanentes se muestran al usuario y no se reintentan.
sealed class AppException implements Exception {
  const AppException(this.message, {this.code});

  /// Mensaje accionable para el usuario (RNF-05).
  final String message;

  /// Código técnico resumido para `last_error`. Nunca contiene tokens ni
  /// datos personales (RNF-11).
  final String? code;

  @override
  String toString() => code == null ? message : '$code: $message';
}

/// Sin conexión, timeout o servidor no disponible (5xx). Se reintenta.
class NetworkException extends AppException {
  const NetworkException(super.message, {super.code});
}

/// Token ausente, inválido o expirado (401). La evidencia se conserva.
class UnauthorizedException extends AppException {
  const UnauthorizedException([
    super.message = 'Tu sesión expiró. Inicia sesión nuevamente.',
  ]) : super(code: 'HTTP_401');
}

/// Credenciales incorrectas. Mensaje genérico: no revela si el correo existe
/// (TC-02).
class InvalidCredentialsException extends AppException {
  const InvalidCredentialsException()
    : super('Correo o contraseña incorrectos.', code: 'INVALID_CREDENTIALS');
}

/// Error que no se resolverá reintentando: asignación inexistente o no
/// vigente, archivo inválido, datos fuera de rango, etc.
class PermanentException extends AppException {
  const PermanentException(super.message, {super.code});
}
