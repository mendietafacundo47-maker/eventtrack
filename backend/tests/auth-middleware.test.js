import './helpers/env.js';

import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import jwt from 'jsonwebtoken';

import { config } from '../src/config/env.js';
import { ROLES } from '../src/config/roles.js';
import { authorize, createAuthenticate } from '../src/middleware/auth.js';
import { signAccessToken } from '../src/services/tokens.js';

const dbUser = {
  id: '11111111-1111-4111-8111-111111111111',
  full_name: 'Ana Prueba',
  email: 'ana@uajms.edu.bo',
  role: ROLES.RESPONSIBLE,
  active: true,
  token_version: 0,
};

const reqWith = (token) => ({
  get: (h) => (h.toLowerCase() === 'authorization' && token ? `Bearer ${token}` : undefined),
});

async function runAuth(req, user = dbUser) {
  const authenticate = createAuthenticate({ findUser: async () => user });
  let called = false;
  await authenticate(req, {}, () => {
    called = true;
  });
  return called;
}

const tokenFor = (u = dbUser) =>
  signAccessToken({ id: u.id, role: u.role, tokenVersion: u.token_version }).token;

describe('authenticate', () => {
  it('acepta un token válido y adjunta req.user', async () => {
    const req = reqWith(tokenFor());
    assert.equal(await runAuth(req), true);
    assert.equal(req.user.id, dbUser.id);
    assert.equal(req.user.role, ROLES.RESPONSIBLE);
  });

  it('rechaza peticiones sin token (401 TOKEN_MISSING)', async () => {
    await assert.rejects(runAuth(reqWith(null)), { status: 401, code: 'TOKEN_MISSING' });
  });

  it('rechaza tokens con firma inválida', async () => {
    const forged = jwt.sign({ role: ROLES.ADMIN, tv: 0 }, 'otro-secreto-cualquiera-de-32-caracteres!!', {
      subject: dbUser.id,
      issuer: config.jwt.issuer,
      audience: config.jwt.audience,
    });
    await assert.rejects(runAuth(reqWith(forged)), { status: 401, code: 'TOKEN_INVALID' });
  });

  it('rechaza el algoritmo "none"', async () => {
    const unsigned = jwt.sign({ role: ROLES.ADMIN, tv: 0 }, null, {
      algorithm: 'none',
      subject: dbUser.id,
    });
    await assert.rejects(runAuth(reqWith(unsigned)), { status: 401, code: 'TOKEN_INVALID' });
  });

  it('TC-23: token expirado → 401 TOKEN_EXPIRED', async () => {
    const expired = jwt.sign({ role: dbUser.role, tv: 0 }, config.jwt.secret, {
      subject: dbUser.id,
      issuer: config.jwt.issuer,
      audience: config.jwt.audience,
      expiresIn: -10,
    });
    await assert.rejects(runAuth(reqWith(expired)), { status: 401, code: 'TOKEN_EXPIRED' });
  });

  it('rechaza tokens revocados (token_version distinto)', async () => {
    await assert.rejects(runAuth(reqWith(tokenFor()), { ...dbUser, token_version: 1 }), {
      status: 401,
      code: 'TOKEN_REVOKED',
    });
  });

  it('rechaza usuarios desactivados aunque el token sea válido', async () => {
    await assert.rejects(runAuth(reqWith(tokenFor()), { ...dbUser, active: false }), {
      status: 401,
      code: 'TOKEN_REVOKED',
    });
  });

  it('usa el rol actual de la base, no el del token', async () => {
    const req = reqWith(tokenFor({ ...dbUser, role: ROLES.ADMIN }));
    await runAuth(req, dbUser);
    assert.equal(req.user.role, ROLES.RESPONSIBLE);
  });
});

describe('authorize (RBAC)', () => {
  const run = (role, ...allowed) => {
    let called = false;
    authorize(...allowed)({ user: role ? { role } : undefined }, {}, () => {
      called = true;
    });
    return called;
  };

  it('permite los roles indicados', () => {
    assert.equal(run(ROLES.ADMIN, ROLES.ADMIN), true);
    assert.equal(run(ROLES.SUPERVISOR, ROLES.ORGANIZER, ROLES.SUPERVISOR), true);
  });

  it('TC-03: rol no permitido → 403', () => {
    assert.throws(() => run(ROLES.RESPONSIBLE, ROLES.ADMIN), { status: 403, code: 'FORBIDDEN' });
  });

  it('sin usuario autenticado → 401', () => {
    assert.throws(() => run(null, ROLES.ADMIN), { status: 401 });
  });

  it('exige declarar al menos un rol', () => {
    assert.throws(() => authorize(), /al menos un rol/);
  });
});
