/**
 * Error con código HTTP y un mensaje seguro para el cliente. El campo `code`
 * es estable para que los clientes Flutter decidan cómo reaccionar.
 */
export class HttpError extends Error {
  constructor(status, message, code = undefined, details = undefined) {
    super(message);
    this.status = status;
    this.code = code ?? `HTTP_${status}`;
    this.details = details;
  }

  static badRequest(message = 'Solicitud inválida.', details) {
    return new HttpError(400, message, 'BAD_REQUEST', details);
  }

  static unauthorized(message = 'No autenticado.', code = 'UNAUTHORIZED') {
    return new HttpError(401, message, code);
  }

  static forbidden(message = 'No tienes permiso para esta operación.') {
    return new HttpError(403, message, 'FORBIDDEN');
  }

  static notFound(message = 'Recurso no encontrado.') {
    return new HttpError(404, message, 'NOT_FOUND');
  }

  static conflict(message, code = 'CONFLICT') {
    return new HttpError(409, message, code);
  }
}
