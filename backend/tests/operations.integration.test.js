// Flujo operativo completo contra PostgreSQL real (base `eventtrack_test`):
// evento → actividad → asignación → evidencia multipart → revisión.
import './helpers/env.js';

import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { readdir, rm } from 'node:fs/promises';
import path from 'node:path';
import { after, before, describe, it } from 'node:test';

import request from 'supertest';

import { createApp } from '../src/app.js';
import { pool } from '../src/config/db.js';
import { config } from '../src/config/env.js';
import { ROLES } from '../src/config/roles.js';
import { hashPassword } from '../src/services/password.js';

const PASSWORD = 'Prueba123';
const app = createApp();
const api = () => request(app);

const people = {
  admin: { email: 'admin.ops@uajms.edu.bo', role: ROLES.ADMIN },
  organizer: { email: 'org.ops@uajms.edu.bo', role: ROLES.ORGANIZER },
  organizer2: { email: 'org2.ops@uajms.edu.bo', role: ROLES.ORGANIZER },
  supervisor: { email: 'sup.ops@uajms.edu.bo', role: ROLES.SUPERVISOR },
  resp: { email: 'resp.ops@uajms.edu.bo', role: ROLES.RESPONSIBLE },
  resp2: { email: 'resp2.ops@uajms.edu.bo', role: ROLES.RESPONSIBLE },
};

// Imágenes mínimas: solo importan los bytes de firma.
const JPEG = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(512, 7)]);
const PNG = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.alloc(256, 1)]);
const EXE = Buffer.concat([Buffer.from('MZ'), Buffer.alloc(512, 0)]);

const as = (who) => ({ Authorization: `Bearer ${people[who].token}` });

let event;
let activity;
let assignment;

function metadata(overrides = {}) {
  return {
    clientUuid: randomUUID(),
    assignmentId: assignment.id,
    latitude: -21.5337,
    longitude: -64.7348,
    accuracyM: 8.5,
    locationStatus: 'AVAILABLE',
    capturedAt: new Date().toISOString(),
    notes: 'Ambiente listo',
    ...overrides,
  };
}

function upload(who, meta, { key = meta.clientUuid, file = JPEG, filename = 'foto.jpg', contentType = 'image/jpeg' } = {}) {
  const req = api().post('/api/v1/evidences').set(as(who));
  if (key !== null) req.set('Idempotency-Key', key);
  req.field('metadata', JSON.stringify(meta));
  if (file) req.attach('photo', file, { filename, contentType });
  return req;
}

before(async () => {
  for (const script of ['scripts/create-db.js', 'scripts/migrate.js']) {
    execFileSync(process.execPath, [script], { env: process.env, stdio: 'pipe' });
  }
  await pool.query(
    'TRUNCATE audit_logs, reviews, evidences, assignments, activities, events, users RESTART IDENTITY CASCADE',
  );
  const hash = await hashPassword(PASSWORD);
  for (const [name, p] of Object.entries(people)) {
    const { rows } = await pool.query(
      `INSERT INTO users (role_id, full_name, email, password_hash)
       SELECT id, $2, $3, $4 FROM roles WHERE code = $1 RETURNING id`,
      [p.role, `Usuario ${name}`, p.email, hash],
    );
    p.id = rows[0].id;
    const res = await api().post('/api/v1/auth/login').send({ email: p.email, password: PASSWORD });
    p.token = res.body.accessToken;
  }
});

after(async () => {
  await pool.end();
  await rm(config.uploads.dir, { recursive: true, force: true });
});

describe('eventos (RF-05, P-01)', () => {
  it('TC-04: el organizador crea un evento válido', async () => {
    const res = await api().post('/api/v1/events').set(as('organizer')).send({
      name: 'Congreso Universitario de Informática',
      description: 'Jornadas académicas',
      locationName: 'Campus central',
      startsAt: '2026-11-20T13:00:00Z',
      endsAt: '2026-11-21T22:00:00Z',
      latitude: -21.5337,
      longitude: -64.7348,
      status: 'ACTIVE',
    });
    assert.equal(res.status, 201, JSON.stringify(res.body));
    assert.equal(res.body.organizer.id, people.organizer.id);
    assert.equal(res.body.status, 'ACTIVE');
    assert.equal(res.body.latitude, -21.5337);
    event = res.body;
  });

  it('TC-05: fin anterior al inicio → 400', async () => {
    const res = await api().post('/api/v1/events').set(as('organizer')).send({
      name: 'Evento inválido',
      startsAt: '2026-11-21T10:00:00Z',
      endsAt: '2026-11-20T10:00:00Z',
    });
    assert.equal(res.status, 400);
    assert.equal(res.body.details[0].field, 'endsAt');
  });

  it('TC-05: PATCH también valida fechas contra las existentes', async () => {
    const res = await api().patch(`/api/v1/events/${event.id}`).set(as('organizer'))
      .send({ endsAt: '2026-11-01T00:00:00Z' });
    assert.equal(res.status, 400);
  });

  it('TC-03: un responsable no puede crear eventos', async () => {
    const res = await api().post('/api/v1/events').set(as('resp')).send({
      name: 'No permitido', startsAt: '2026-11-20T10:00:00Z', endsAt: '2026-11-20T12:00:00Z',
    });
    assert.equal(res.status, 403);
  });

  it('otro organizador no ve ni modifica el evento', async () => {
    const get = await api().get(`/api/v1/events/${event.id}`).set(as('organizer2'));
    assert.equal(get.status, 404);
    const patch = await api().patch(`/api/v1/events/${event.id}`).set(as('organizer2')).send({ name: 'Hackeado' });
    assert.equal(patch.status, 404);
    const list = await api().get('/api/v1/events').set(as('organizer2'));
    assert.equal(list.body.total, 0);
  });

  it('el supervisor ve todos los eventos', async () => {
    const res = await api().get('/api/v1/events').set(as('supervisor'));
    assert.equal(res.status, 200);
    assert.equal(res.body.total, 1);
  });

  it('transición de estado no permitida → 409', async () => {
    const res = await api().patch(`/api/v1/events/${event.id}`).set(as('organizer')).send({ status: 'DRAFT' });
    assert.equal(res.status, 409);
    assert.equal(res.body.code, 'INVALID_TRANSITION');
  });
});

describe('actividades y asignaciones (RF-06, RF-07, RF-08)', () => {
  it('crea una actividad en el evento', async () => {
    const res = await api().post(`/api/v1/events/${event.id}/activities`).set(as('organizer')).send({
      title: 'Acreditación de expositores',
      description: 'Entrega de credenciales',
      dueAt: '2026-11-20T15:00:00Z',
    });
    assert.equal(res.status, 201, JSON.stringify(res.body));
    assert.equal(res.body.status, 'PENDING');
    activity = res.body;
  });

  it('un responsable sin asignación no ve el evento', async () => {
    const res = await api().get(`/api/v1/events/${event.id}/activities`).set(as('resp'));
    assert.equal(res.status, 404);
  });

  it('TC-06: asigna la actividad a un responsable activo', async () => {
    const res = await api().post('/api/v1/assignments').set(as('organizer'))
      .send({ activityId: activity.id, userId: people.resp.id });
    assert.equal(res.status, 201, JSON.stringify(res.body));
    assignment = res.body;

    const dup = await api().post('/api/v1/assignments').set(as('organizer'))
      .send({ activityId: activity.id, userId: people.resp.id });
    assert.equal(dup.status, 409);
  });

  it('no se puede asignar a un usuario que no es responsable', async () => {
    const res = await api().post('/api/v1/assignments').set(as('organizer'))
      .send({ activityId: activity.id, userId: people.supervisor.id });
    assert.equal(res.status, 400);
  });

  it('P-03: GET /me/assignments devuelve el formato que usa Flutter', async () => {
    const res = await api().get('/api/v1/me/assignments').set(as('resp'));
    assert.equal(res.status, 200);
    assert.equal(res.body.length, 1);
    const a = res.body[0];
    assert.equal(a.id, assignment.id);
    assert.equal(a.activity.title, 'Acreditación de expositores');
    assert.equal(a.activity.status, 'PENDING');
    assert.equal(a.event.name, event.name);
    assert.equal(a.event.latitude, -21.5337);

    const other = await api().get('/api/v1/me/assignments').set(as('resp2'));
    assert.deepEqual(other.body, []);
  });
});

describe('recepción de evidencias (P-06, RF-09 a RF-14)', () => {
  let first;

  it('TC-10/TC-14: recibe evidencia multipart con GPS y precisión', async () => {
    const meta = metadata();
    const res = await upload('resp', meta);
    assert.equal(res.status, 201, JSON.stringify(res.body));
    assert.equal(res.body.clientUuid, meta.clientUuid);
    assert.equal(res.body.status, 'PENDING_REVIEW');
    assert.ok(res.body.receivedAt);
    first = { meta, receipt: res.body };

    const { rows } = await pool.query('SELECT * FROM evidences WHERE id = $1', [res.body.id]);
    assert.equal(rows[0].latitude, -21.5337);
    assert.equal(rows[0].accuracy_m, 8.5);
    assert.equal(rows[0].photo_mime, 'image/jpeg');
    assert.equal(rows[0].photo_size_bytes, JPEG.length);
    assert.match(rows[0].photo_sha256, /^[0-9a-f]{64}$/);
    // Nombre generado por el servidor, no el del cliente.
    assert.match(rows[0].photo_path, new RegExp(`^evidences/\\d{4}/\\d{2}/${res.body.id}\\.jpg$`));
    // Hora de captura y de recepción separadas.
    assert.notEqual(rows[0].captured_at.toISOString(), rows[0].received_at.toISOString());
  });

  it('la actividad pasa a SUBMITTED al recibir evidencia', async () => {
    const { rows } = await pool.query('SELECT status FROM activities WHERE id = $1', [activity.id]);
    assert.equal(rows[0].status, 'SUBMITTED');
  });

  it('TC-15: reintento con el mismo UUID devuelve la misma evidencia', async () => {
    const res = await upload('resp', first.meta);
    assert.equal(res.status, 200);
    assert.equal(res.headers['idempotent-replayed'], 'true');
    assert.equal(res.body.id, first.receipt.id);
    const { rows } = await pool.query('SELECT count(*)::int AS n FROM evidences WHERE client_uuid = $1', [first.meta.clientUuid]);
    assert.equal(rows[0].n, 1);
  });

  it('TC-15: reintentos concurrentes crean una sola evidencia', async () => {
    const meta = metadata();
    const results = await Promise.all([upload('resp', meta), upload('resp', meta), upload('resp', meta)]);
    const statuses = results.map((r) => r.status).sort();
    assert.deepEqual(statuses, [200, 200, 201]);
    assert.equal(new Set(results.map((r) => r.body.id)).size, 1);
    const { rows } = await pool.query('SELECT count(*)::int AS n FROM evidences WHERE client_uuid = $1', [meta.clientUuid]);
    assert.equal(rows[0].n, 1);
  });

  it('la misma clave usada por otro usuario → 409', async () => {
    await pool.query(
      `INSERT INTO assignments (activity_id, user_id, assigned_by) VALUES ($1, $2, $3)`,
      [activity.id, people.resp2.id, people.organizer.id],
    );
    const { rows } = await pool.query('SELECT id FROM assignments WHERE user_id = $1', [people.resp2.id]);
    const res = await upload('resp2', { ...first.meta, assignmentId: rows[0].id });
    assert.equal(res.status, 409);
    assert.equal(res.body.code, 'IDEMPOTENCY_KEY_REUSED');
  });

  it('sin cabecera Idempotency-Key → 400', async () => {
    const res = await upload('resp', metadata(), { key: null });
    assert.equal(res.status, 400);
    assert.equal(res.body.code, 'IDEMPOTENCY_KEY_REQUIRED');
  });

  it('cabecera distinta de metadata.clientUuid → 400', async () => {
    const res = await upload('resp', metadata(), { key: randomUUID() });
    assert.equal(res.status, 400);
    assert.equal(res.body.code, 'IDEMPOTENCY_KEY_MISMATCH');
  });

  it('TC-07: un responsable sin esa asignación → 403', async () => {
    const res = await upload('resp2', metadata());
    assert.equal(res.status, 403);
    assert.equal(res.body.code, 'NOT_ASSIGNED');
  });

  it('un supervisor no puede subir evidencias', async () => {
    const res = await upload('supervisor', metadata());
    assert.equal(res.status, 403);
  });

  it('TC-11 / RB-07: sin GPS se guarda con coordenadas nulas', async () => {
    const res = await upload('resp', metadata({
      latitude: null, longitude: null, accuracyM: null, locationStatus: 'PERMISSION_DENIED',
    }), { file: PNG, filename: 'foto.png', contentType: 'image/png' });
    assert.equal(res.status, 201, JSON.stringify(res.body));
    const { rows } = await pool.query('SELECT latitude, location_status, photo_mime FROM evidences WHERE id = $1', [res.body.id]);
    assert.equal(rows[0].latitude, null);
    assert.equal(rows[0].location_status, 'PERMISSION_DENIED');
    assert.equal(rows[0].photo_mime, 'image/png');
  });

  it('AVAILABLE sin coordenadas → 400', async () => {
    const res = await upload('resp', metadata({ latitude: null, longitude: null }));
    assert.equal(res.status, 400);
  });

  it('TC-12: latitud 120 / longitud 200 → 400', async () => {
    const res = await upload('resp', metadata({ latitude: 120, longitude: 200 }));
    assert.equal(res.status, 400);
    assert.ok(res.body.details.some((d) => d.field === 'metadata.latitude'));
  });

  it('TC-17: ejecutable disfrazado de JPG → 415', async () => {
    const res = await upload('resp', metadata(), { file: EXE, filename: 'foto.jpg' });
    assert.equal(res.status, 415);
  });

  it('TC-17: extensión no permitida → 415', async () => {
    const res = await upload('resp', metadata(), { filename: 'virus.exe' });
    assert.equal(res.status, 415);
  });

  it('TC-18: imagen sobre el límite configurado → 413', async () => {
    const big = Buffer.concat([JPEG, Buffer.alloc(config.uploads.maxPhotoBytes + 1)]);
    const res = await upload('resp', metadata(), { file: big });
    assert.equal(res.status, 413);
    assert.equal(res.body.code, 'FILE_TOO_LARGE');
  });

  it('sin foto → 400', async () => {
    const res = await upload('resp', metadata(), { file: null });
    assert.equal(res.status, 400);
    assert.equal(res.body.code, 'PHOTO_REQUIRED');
  });

  it('no deja archivos temporales ni huérfanos', async () => {
    const tmp = await readdir(path.join(config.uploads.dir, 'tmp'));
    assert.deepEqual(tmp, []);
    const { rows } = await pool.query('SELECT count(*)::int AS n FROM evidences');
    const stored = await readdir(path.join(config.uploads.dir, 'evidences'), { recursive: true });
    assert.equal(stored.filter((f) => /\.(jpg|png|webp)$/.test(f)).length, rows[0].n);
  });

  it('la foto solo la ven usuarios autorizados', async () => {
    const id = first.receipt.id;
    const own = await api().get(`/api/v1/evidences/${id}/photo`).set(as('resp'));
    assert.equal(own.status, 200);
    assert.equal(own.headers['content-type'], 'image/jpeg');
    assert.equal(own.headers['cache-control'], 'private, no-store');
    assert.deepEqual(Buffer.from(own.body), JPEG);

    assert.equal((await api().get(`/api/v1/evidences/${id}/photo`).set(as('supervisor'))).status, 200);
    assert.equal((await api().get(`/api/v1/evidences/${id}/photo`).set(as('resp2'))).status, 404);
    assert.equal((await api().get(`/api/v1/evidences/${id}/photo`).set(as('organizer2'))).status, 404);
    assert.equal((await api().get(`/api/v1/evidences/${id}/photo`)).status, 401);
  });

  it('GET /evidences/:id incluye distancia al evento como indicador', async () => {
    const res = await api().get(`/api/v1/evidences/${first.receipt.id}`).set(as('organizer'));
    assert.equal(res.status, 200);
    assert.equal(res.body.location.distanceToEventM, 0);
    assert.equal(res.body.event.id, event.id);
    assert.deepEqual(res.body.reviews, []);
  });
});

describe('revisión (P-07, RF-15, RB-08, RB-09)', () => {
  let toReject;
  let toApprove;

  before(async () => {
    const { rows } = await pool.query(
      `SELECT ev.id FROM evidences ev JOIN assignments a ON a.id = ev.assignment_id
        WHERE a.user_id = $1 ORDER BY ev.received_at`,
      [people.resp.id],
    );
    [toReject, toApprove] = rows.map((r) => r.id);
  });

  it('bandeja de pendientes para el supervisor', async () => {
    const res = await api().get('/api/v1/evidences?status=PENDING_REVIEW').set(as('supervisor'));
    assert.equal(res.status, 200);
    assert.equal(res.body.total, 3);
  });

  it('un responsable no puede revisar', async () => {
    const res = await api().post(`/api/v1/evidences/${toReject}/reviews`).set(as('resp'))
      .send({ result: 'APPROVED' });
    assert.equal(res.status, 403);
  });

  it('TC-20: rechazo sin comentario → 400', async () => {
    const res = await api().post(`/api/v1/evidences/${toReject}/reviews`).set(as('supervisor'))
      .send({ result: 'REJECTED', comment: '   ' });
    assert.equal(res.status, 400);
    assert.equal(res.body.details[0].field, 'comment');
  });

  it('rechazo con motivo; la actividad sigue SUBMITTED si hay otras pendientes', async () => {
    const res = await api().post(`/api/v1/evidences/${toReject}/reviews`).set(as('supervisor'))
      .send({ result: 'REJECTED', comment: 'La foto no muestra el ambiente.' });
    assert.equal(res.status, 201, JSON.stringify(res.body));
    assert.equal(res.body.evidence.status, 'REJECTED');
    assert.equal(res.body.activity.status, 'SUBMITTED');
  });

  it('una evidencia ya revisada no se revisa de nuevo → 409', async () => {
    const res = await api().post(`/api/v1/evidences/${toReject}/reviews`).set(as('supervisor'))
      .send({ result: 'APPROVED' });
    assert.equal(res.status, 409);
    assert.equal(res.body.code, 'ALREADY_REVIEWED');
  });

  it('TC-19: aprobación registra revisor y completa la actividad', async () => {
    const res = await api().post(`/api/v1/evidences/${toApprove}/reviews`).set(as('supervisor'))
      .send({ result: 'APPROVED', comment: 'Correcto' });
    assert.equal(res.status, 201);
    assert.equal(res.body.review.reviewer.id, people.supervisor.id);
    assert.equal(res.body.activity.status, 'COMPLETED');

    const detail = await api().get(`/api/v1/evidences/${toApprove}`).set(as('resp'));
    assert.equal(detail.body.status, 'APPROVED');
    assert.equal(detail.body.reviews[0].reviewer.id, people.supervisor.id);
  });

  it('una actividad completada ya no acepta evidencias', async () => {
    const res = await upload('resp', metadata());
    assert.equal(res.status, 409);
    assert.equal(res.body.code, 'ACTIVITY_LOCKED');
  });

  it('RF-18: auditoría sin coordenadas', async () => {
    const { rows } = await pool.query(
      `SELECT action, metadata::text AS m FROM audit_logs
        WHERE action LIKE 'EVIDENCE_%' OR action LIKE 'EVENT_%' OR action LIKE 'ACTIVITY_%'`,
    );
    const actions = new Set(rows.map((r) => r.action));
    for (const a of ['EVENT_CREATED', 'ACTIVITY_CREATED', 'EVIDENCE_RECEIVED', 'EVIDENCE_APPROVED', 'EVIDENCE_REJECTED']) {
      assert.ok(actions.has(a), a);
    }
    for (const r of rows) assert.ok(!r.m.includes('-21.53'), r.m);
  });

  it('un evento cerrado no acepta nuevas actividades', async () => {
    const close = await api().patch(`/api/v1/events/${event.id}`).set(as('organizer')).send({ status: 'CLOSED' });
    assert.equal(close.status, 200);
    const res = await api().post(`/api/v1/events/${event.id}/activities`).set(as('organizer'))
      .send({ title: 'Tarea tardía' });
    assert.equal(res.status, 409);
    assert.equal(res.body.code, 'EVENT_LOCKED');
  });
});

describe('reportes y panel web (RF-17, P-08)', () => {
  it('TC-21: los totales del reporte coinciden con los registros', async () => {
    const res = await api().get(`/api/v1/reports/events/${event.id}`).set(as('supervisor'));
    assert.equal(res.status, 200, JSON.stringify(res.body));
    const r = res.body;

    const { rows } = await pool.query(
      `SELECT
         (SELECT count(*)::int FROM activities WHERE event_id = $1) AS activities,
         (SELECT count(*)::int FROM evidences ev JOIN assignments a ON a.id = ev.assignment_id
            JOIN activities ac ON ac.id = a.activity_id WHERE ac.event_id = $1) AS evidences,
         (SELECT count(*)::int FROM evidences ev JOIN assignments a ON a.id = ev.assignment_id
            JOIN activities ac ON ac.id = a.activity_id
           WHERE ac.event_id = $1 AND ev.status = 'APPROVED') AS approved,
         (SELECT count(*)::int FROM reviews) AS reviews,
         (SELECT count(*)::int FROM assignments a JOIN activities ac ON ac.id = a.activity_id
           WHERE ac.event_id = $1 AND a.status = 'ACTIVE') AS assignments`,
      [event.id],
    );
    const db = rows[0];
    assert.equal(r.activities.total, db.activities);
    assert.equal(r.evidences.total, db.evidences);
    assert.equal(r.evidences.approved, db.approved);
    assert.equal(r.reviews.total, db.reviews);
    assert.equal(r.assignments.active, db.assignments);

    // Estado conocido tras las pruebas anteriores.
    assert.equal(r.activities.byStatus.COMPLETED, 1);
    assert.equal(r.activities.open, 0);
    assert.equal(r.completionRate, 100);
    assert.deepEqual(
      { ...r.evidences },
      { total: 3, pendingReview: 1, approved: 1, rejected: 1, withLocation: 2, withoutLocation: 1 },
    );
    assert.equal(r.items[0].title, 'Acreditación de expositores');
    assert.equal(r.items[0].evidences.total, 3);
    assert.ok(r.items[0].responsibles.includes('Usuario resp'));
  });

  it('el reporte respeta el acceso por rol y por evento', async () => {
    const url = `/api/v1/reports/events/${event.id}`;
    assert.equal((await api().get(url).set(as('organizer'))).status, 200);
    assert.equal((await api().get(url).set(as('admin'))).status, 200);
    assert.equal((await api().get(url).set(as('organizer2'))).status, 404);
    assert.equal((await api().get(url).set(as('resp'))).status, 403);
    assert.equal((await api().get(url)).status, 401);
  });

  it('lista de responsables asignables solo para organizador/administrador', async () => {
    const res = await api().get('/api/v1/assignments/assignable-users').set(as('organizer'));
    assert.equal(res.status, 200);
    const emails = res.body.map((u) => u.email).sort();
    assert.deepEqual(emails, [people.resp.email, people.resp2.email].sort());
    assert.deepEqual(Object.keys(res.body[0]).sort(), ['email', 'fullName', 'id']);
    assert.equal((await api().get('/api/v1/assignments/assignable-users').set(as('supervisor'))).status, 403);
  });

  it('CORS: permite el panel web en localhost y rechaza otros orígenes', async () => {
    const ok = await api().options('/api/v1/events')
      .set('Origin', 'http://localhost:51234')
      .set('Access-Control-Request-Method', 'GET')
      .set('Access-Control-Request-Headers', 'authorization');
    assert.equal(ok.headers['access-control-allow-origin'], 'http://localhost:51234');

    const bad = await api().options('/api/v1/events')
      .set('Origin', 'https://sitio-malicioso.example')
      .set('Access-Control-Request-Method', 'GET');
    assert.equal(bad.headers['access-control-allow-origin'], undefined);
  });
});
