import jwt from 'jsonwebtoken';

import { config } from '../config/env.js';

const { secret, expiresIn, issuer, audience } = config.jwt;

/**
 * Token de acceso firmado con HS256 y expiración (§4.3.7).
 * `tv` (token_version) permite revocar todos los tokens de un usuario.
 */
export function signAccessToken(user) {
  const token = jwt.sign({ role: user.role, tv: user.tokenVersion }, secret, {
    algorithm: 'HS256',
    subject: user.id,
    expiresIn,
    issuer,
    audience,
  });
  const { exp } = jwt.decode(token);
  return { token, expiresAt: new Date(exp * 1000) };
}

/**
 * Verifica firma, algoritmo, emisor, audiencia y expiración.
 * Lanza `jwt.TokenExpiredError` o `jwt.JsonWebTokenError`.
 */
export function verifyAccessToken(token) {
  return jwt.verify(token, secret, {
    algorithms: ['HS256'],
    issuer,
    audience,
  });
}
