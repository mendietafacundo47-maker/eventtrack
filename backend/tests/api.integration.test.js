// Pruebas de integración contra PostgreSQL real (base `eventtrack_test`).
// Requiere el servidor PostgreSQL configurado en .env.
import './helpers/env.js';

import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { after, before, describe, it } from 'node:test';

import request from 'supertest';

import { createApp } from '../src/app.js';
import { pool } from '../src/config/db.js';
import { ROLES } from '../src/config/roles.js';
import { hashPassword } from '../src/services/password.js';

const PASSWORD = 'Prueba123';
const app = createApp();
const api = () => request(app);

const users = {
  admin: { email: 'admin.test@uajms.edu.bo', fullName: 'Admin Test', role: ROLES.ADMIN },
  responsible: { email: 'resp.test@uajms.edu.bo', fullName: 'Resp Test', role: ROLES.RESPONSIBLE },
  supervisor: { email: 'sup.test@uajms.edu.bo', fullName: 'Sup Test', role: ROLES.SUPERVISOR },
};

async function login(email, password = PASSWORD) {
  const res = await api().post('/api/v1/auth/login').send({ email, password });
  return res;
}

async function tokenOf(user) {
  const res = await login(user.email);
  assert.equal(res.status, 200, JSON.stringify(res.body));
  return res.body.accessToken;
}

before(async () => {
  for (const script of ['scripts/create-db.js', 'scripts/migrate.js']) {
    execFileSync(process.execPath, [script], { env: process.env, stdio: 'pipe' });
  }
  await pool.query(
    'TRUNCATE audit_logs, reviews, evidences, assignments, activities, events, users RESTART IDENTITY CASCADE',
  );
  const hash = await hashPassword(PASSWORD);
  for (const u of Object.values(users)) {
    const { rows } = await pool.query(
      `INSERT INTO users (role_id, full_name, email, password_hash)
       SELECT id, $2, $3, $4 FROM roles WHERE code = $1 RETURNING id`,
      [u.role, u.fullName, u.email, hash],
    );
    u.id = rows[0].id;
  }
});

after(() => pool.end());

describe('salud', () => {
  it('GET /health responde ok con base de datos', async () => {
    const res = await api().get('/api/v1/health');
    assert.equal(res.status, 200);
    assert.deepEqual(res.body, { status: 'ok', database: 'ok' });
  });
});

describe('autenticación (RF-01, RF-02, RNF-01)', () => {
  it('TC-01: login válido devuelve token y rol, sin hash', async () => {
    const res = await login('  ADMIN.test@uajms.edu.bo ');
    assert.equal(res.status, 200);
    assert.equal(res.body.tokenType, 'Bearer');
    assert.ok(res.body.accessToken.split('.').length === 3);
    assert.deepEqual(res.body.user, {
      id: users.admin.id,
      fullName: 'Admin Test',
      email: users.admin.email,
      role: ROLES.ADMIN,
    });
  });

  it('TC-02: contraseña incorrecta y correo inexistente dan el mismo mensaje', async () => {
    const wrong = await login(users.admin.email, 'Incorrecta1');
    const unknown = await login('nadie@uajms.edu.bo', 'Incorrecta1');
    assert.equal(wrong.status, 401);
    assert.equal(unknown.status, 401);
    assert.deepEqual(wrong.body, unknown.body);
    assert.equal(wrong.body.code, 'INVALID_CREDENTIALS');
  });

  it('valida el formato del cuerpo', async () => {
    const res = await api().post('/api/v1/auth/login').send({ email: 'no-es-correo' });
    assert.equal(res.status, 400);
    assert.equal(res.body.code, 'BAD_REQUEST');
  });

  it('RNF-01: la contraseña se guarda con hash bcrypt', async () => {
    const { rows } = await pool.query('SELECT password_hash FROM users WHERE id = $1', [users.admin.id]);
    assert.match(rows[0].password_hash, /^\$2[aby]\$10\$/);
    assert.ok(!rows[0].password_hash.includes(PASSWORD));
  });

  it('GET /me devuelve el perfil del token', async () => {
    const token = await tokenOf(users.responsible);
    const res = await api().get('/api/v1/me').set('Authorization', `Bearer ${token}`);
    assert.equal(res.status, 200);
    assert.equal(res.body.role, ROLES.RESPONSIBLE);
  });

  it('GET /me sin token → 401', async () => {
    const res = await api().get('/api/v1/me');
    assert.equal(res.status, 401);
    assert.equal(res.body.code, 'TOKEN_MISSING');
  });

  it('RF-02: tras logout el token deja de ser válido', async () => {
    const token = await tokenOf(users.supervisor);
    const out = await api().post('/api/v1/auth/logout').set('Authorization', `Bearer ${token}`);
    assert.equal(out.status, 204);
    const res = await api().get('/api/v1/me').set('Authorization', `Bearer ${token}`);
    assert.equal(res.status, 401);
    assert.equal(res.body.code, 'TOKEN_REVOKED');
  });

  it('registra login y logout en audit_logs sin datos sensibles', async () => {
    const { rows } = await pool.query(
      `SELECT action, metadata::text AS m FROM audit_logs WHERE action IN ('LOGIN', 'LOGIN_FAILED', 'LOGOUT')`,
    );
    assert.ok(rows.some((r) => r.action === 'LOGIN'));
    assert.ok(rows.some((r) => r.action === 'LOGOUT'));
    for (const r of rows) assert.ok(!r.m.includes(PASSWORD) && !r.m.includes('eyJ'));
  });
});

describe('RBAC en /users (RF-03, RF-04, RNF-02)', () => {
  it('TC-03: un responsable no puede listar usuarios (403)', async () => {
    const token = await tokenOf(users.responsible);
    const res = await api().get('/api/v1/users').set('Authorization', `Bearer ${token}`);
    assert.equal(res.status, 403);
    assert.equal(res.body.items, undefined);
  });

  it('el administrador lista usuarios sin exponer hashes', async () => {
    const token = await tokenOf(users.admin);
    const res = await api()
      .get('/api/v1/users?role=RESPONSIBLE')
      .set('Authorization', `Bearer ${token}`);
    assert.equal(res.status, 200);
    assert.equal(res.body.total, 1);
    assert.equal(res.body.items[0].email, users.responsible.email);
    assert.ok(!JSON.stringify(res.body).includes('password'));
    assert.ok(!JSON.stringify(res.body).includes('$2'));
  });

  it('crea usuarios, valida contraseñas débiles y correos duplicados', async () => {
    const token = await tokenOf(users.admin);
    const auth = { Authorization: `Bearer ${token}` };

    const weak = await api().post('/api/v1/users').set(auth)
      .send({ fullName: 'Nuevo Usuario', email: 'nuevo@uajms.edu.bo', role: 'ORGANIZER', password: 'corta' });
    assert.equal(weak.status, 400);

    const ok = await api().post('/api/v1/users').set(auth)
      .send({ fullName: 'Nuevo Usuario', email: 'Nuevo@UAJMS.edu.bo', role: 'ORGANIZER', password: 'Segura123' });
    assert.equal(ok.status, 201);
    assert.equal(ok.body.email, 'nuevo@uajms.edu.bo');
    assert.equal(ok.body.role, ROLES.ORGANIZER);

    const dup = await api().post('/api/v1/users').set(auth)
      .send({ fullName: 'Otro', email: 'nuevo@uajms.edu.bo', role: 'ORGANIZER', password: 'Segura123' });
    assert.equal(dup.status, 409);
    assert.equal(dup.body.code, 'EMAIL_TAKEN');

    const login1 = await login('nuevo@uajms.edu.bo', 'Segura123');
    assert.equal(login1.status, 200);
  });

  it('desactivar una cuenta revoca su token y bloquea el login', async () => {
    const admin = await tokenOf(users.admin);
    const victim = await tokenOf(users.responsible);

    const res = await api()
      .patch(`/api/v1/users/${users.responsible.id}`)
      .set('Authorization', `Bearer ${admin}`)
      .send({ active: false });
    assert.equal(res.status, 200);
    assert.equal(res.body.active, false);

    const me = await api().get('/api/v1/me').set('Authorization', `Bearer ${victim}`);
    assert.equal(me.status, 401);
    const again = await login(users.responsible.email);
    assert.equal(again.status, 401);
    assert.equal(again.body.code, 'INVALID_CREDENTIALS');

    // Reactivar para no afectar otras pruebas.
    await api().patch(`/api/v1/users/${users.responsible.id}`)
      .set('Authorization', `Bearer ${admin}`).send({ active: true });
  });

  it('el administrador no puede desactivarse a sí mismo', async () => {
    const token = await tokenOf(users.admin);
    const res = await api()
      .patch(`/api/v1/users/${users.admin.id}`)
      .set('Authorization', `Bearer ${token}`)
      .send({ active: false });
    assert.equal(res.status, 400);
  });

  it('rechaza campos no permitidos e identificadores inválidos', async () => {
    const token = await tokenOf(users.admin);
    const auth = { Authorization: `Bearer ${token}` };
    const extra = await api().patch(`/api/v1/users/${users.responsible.id}`).set(auth)
      .send({ email: 'cambio@uajms.edu.bo' });
    assert.equal(extra.status, 400);
    const badId = await api().get('/api/v1/users/123').set(auth);
    assert.equal(badId.status, 400);
  });
});

describe('errores', () => {
  it('ruta inexistente → 404 JSON', async () => {
    const res = await api().get('/api/v1/no-existe');
    assert.equal(res.status, 404);
    assert.equal(res.body.code, 'NOT_FOUND');
  });

  it('JSON mal formado → 400', async () => {
    const res = await api()
      .post('/api/v1/auth/login')
      .set('Content-Type', 'application/json')
      .send('{"email":');
    assert.equal(res.status, 400);
    assert.equal(res.body.code, 'BAD_JSON');
  });
});
