import { HttpError } from '../utils/http-error.js';

/**
 * Valida `req[source]` con un esquema Zod. El resultado limpio queda en
 * `req.valid[source]` (en Express 5 `req.query` es de solo lectura).
 *
 * @param {import('zod').ZodType} schema
 * @param {'body'|'query'|'params'} [source]
 */
export function validate(schema, source = 'body') {
  return function validateRequest(req, _res, next) {
    const result = schema.safeParse(req[source] ?? {});
    if (!result.success) {
      const details = result.error.issues.map((i) => ({
        field: i.path.join('.'),
        message: i.message,
      }));
      throw HttpError.badRequest('Datos inválidos.', details);
    }
    req.valid ??= {};
    req.valid[source] = result.data;
    next();
  };
}
