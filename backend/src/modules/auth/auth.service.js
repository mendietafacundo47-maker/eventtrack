import { audit } from '../../services/audit.js';
import { verifyAgainstDummy, verifyPassword } from '../../services/password.js';
import { signAccessToken } from '../../services/tokens.js';
import { HttpError } from '../../utils/http-error.js';
import * as users from '../users/users.repository.js';

// Mismo mensaje para correo inexistente, contraseña incorrecta o cuenta
// desactivada: no se revela qué falló (TC-02).
const invalidCredentials = () =>
  HttpError.unauthorized('Correo o contraseña incorrectos.', 'INVALID_CREDENTIALS');

/** RF-01: inicio de sesión con credenciales válidas. */
export async function login({ email, password }, { ip } = {}) {
  const row = await users.findByEmailWithHash(email);

  const valid = row
    ? await verifyPassword(password, row.password_hash)
    : await verifyAgainstDummy(password);

  if (!row || !valid || !row.active) {
    await audit({
      actorId: row?.id ?? null,
      action: 'LOGIN_FAILED',
      entity: 'auth',
      metadata: { reason: !row ? 'unknown_user' : !valid ? 'bad_password' : 'inactive' },
      ip,
    });
    throw invalidCredentials();
  }

  const { token, expiresAt } = signAccessToken({
    id: row.id,
    role: row.role,
    tokenVersion: row.token_version,
  });
  await users.touchLastLogin(row.id);
  await audit({ actorId: row.id, action: 'LOGIN', entity: 'auth', entityId: row.id, ip });

  return {
    accessToken: token,
    tokenType: 'Bearer',
    expiresAt: expiresAt.toISOString(),
    user: { id: row.id, fullName: row.full_name, email: row.email, role: row.role },
  };
}

/**
 * RF-02: cierre de sesión. Al ser tokens sin estado, se incrementa
 * `token_version`, lo que invalida todos los tokens del usuario (en todos
 * sus dispositivos).
 */
export async function logout(user, { ip } = {}) {
  await users.revokeTokens(user.id);
  await audit({ actorId: user.id, action: 'LOGOUT', entity: 'auth', entityId: user.id, ip });
}
