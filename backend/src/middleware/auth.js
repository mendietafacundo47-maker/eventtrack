import jwt from 'jsonwebtoken';

import { findAuthUserById } from '../modules/users/users.repository.js';
import { verifyAccessToken } from '../services/tokens.js';
import { HttpError } from '../utils/http-error.js';

/**
 * Crea el middleware de autenticación. `findUser` es inyectable para pruebas.
 *
 * Además de validar el JWT, consulta al usuario en cada petición para que
 * una cuenta desactivada, un cambio de rol o un cierre de sesión surtan
 * efecto inmediatamente (RNF-02).
 */
export function createAuthenticate({ findUser = findAuthUserById } = {}) {
  return async function authenticate(req, _res, next) {
    const header = req.get('authorization') ?? '';
    const [scheme, token] = header.split(' ');
    if (scheme !== 'Bearer' || !token) {
      throw HttpError.unauthorized('Se requiere un token de acceso.', 'TOKEN_MISSING');
    }

    let payload;
    try {
      payload = verifyAccessToken(token);
    } catch (err) {
      if (err instanceof jwt.TokenExpiredError) {
        throw HttpError.unauthorized('La sesión expiró. Inicia sesión nuevamente.', 'TOKEN_EXPIRED');
      }
      throw HttpError.unauthorized('Token de acceso inválido.', 'TOKEN_INVALID');
    }

    const user = await findUser(payload.sub);
    if (!user || !user.active || user.token_version !== payload.tv) {
      throw HttpError.unauthorized('La sesión ya no es válida.', 'TOKEN_REVOKED');
    }

    req.user = {
      id: user.id,
      role: user.role,
      fullName: user.full_name,
      email: user.email,
      tokenVersion: user.token_version,
    };
    next();
  };
}

export const authenticate = createAuthenticate();

/**
 * Autorización por rol (RBAC). Debe ir después de `authenticate`.
 * La interfaz puede ocultar botones, pero el control real ocurre aquí
 * (§4.3.7, TC-03).
 *
 *   router.get('/users', authenticate, authorize(ROLES.ADMIN), handler)
 *
 * @param {...string} allowedRoles
 */
export function authorize(...allowedRoles) {
  if (allowedRoles.length === 0) {
    throw new Error('authorize() requiere al menos un rol');
  }
  const allowed = new Set(allowedRoles);
  return function authorizeRole(req, _res, next) {
    if (!req.user) throw HttpError.unauthorized();
    if (!allowed.has(req.user.role)) throw HttpError.forbidden();
    next();
  };
}
