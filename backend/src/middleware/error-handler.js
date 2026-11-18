import { logger } from '../config/logger.js';
import { HttpError } from '../utils/http-error.js';
import { isMulterError, multerErrorCodes } from './upload.js';

export function notFoundHandler(req, _res, next) {
  next(HttpError.notFound(`Ruta no encontrada: ${req.method} ${req.path}`));
}

// Códigos de error de PostgreSQL más comunes.
const PG_ERRORS = {
  23505: [409, 'El registro ya existe.', 'DUPLICATE'],
  23503: [409, 'El registro referenciado no existe o está en uso.', 'FK_VIOLATION'],
  23514: [400, 'Los datos no cumplen las reglas de validación.', 'CHECK_VIOLATION'],
  23502: [400, 'Falta un dato obligatorio.', 'NOT_NULL_VIOLATION'],
  '22P02': [400, 'Formato de dato inválido.', 'INVALID_TEXT'],
};

// eslint-disable-next-line no-unused-vars
export function errorHandler(err, req, res, _next) {
  if (err instanceof HttpError) {
    return res.status(err.status).json({
      message: err.message,
      code: err.code,
      ...(err.details ? { details: err.details } : {}),
    });
  }

  if (err?.type === 'entity.parse.failed') {
    return res.status(400).json({ message: 'JSON mal formado.', code: 'BAD_JSON' });
  }
  if (err?.type === 'entity.too.large') {
    return res.status(413).json({ message: 'El cuerpo es demasiado grande.', code: 'PAYLOAD_TOO_LARGE' });
  }

  if (isMulterError(err)) {
    const [status, message, code] = multerErrorCodes[err.code] ?? [400, 'Formulario multipart inválido.', 'BAD_MULTIPART'];
    return res.status(status).json({ message, code });
  }
  if (err?.message === 'Multipart: Boundary not found' || err?.message === 'Unexpected end of form') {
    return res.status(400).json({ message: 'Formulario multipart inválido.', code: 'BAD_MULTIPART' });
  }

  const pg = PG_ERRORS[err?.code];
  if (pg) {
    const [status, message, code] = pg;
    // `constraint` ayuda a diagnosticar sin exponer datos.
    return res.status(status).json({ message, code, constraint: err.constraint });
  }

  // Error no controlado: se registra completo pero al cliente solo se le
  // devuelve un mensaje genérico (no se exponen trazas ni SQL).
  (req.log ?? logger).error({ err }, 'Error no controlado');
  return res.status(500).json({ message: 'Error interno del servidor.', code: 'INTERNAL' });
}
