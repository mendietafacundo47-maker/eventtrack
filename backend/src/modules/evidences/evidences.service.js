import { randomUUID } from 'node:crypto';

import { z } from 'zod';

import { query, withTransaction } from '../../config/db.js';
import { ROLES } from '../../config/roles.js';
import { audit } from '../../services/audit.js';
import {
  detectImageMime,
  removeQuietly,
  resolveStoredPath,
  sha256File,
  storePhoto,
} from '../../services/photo-storage.js';
import { HttpError } from '../../utils/http-error.js';
import { isEventOpen } from '../events/event-access.js';

const LOCATION_STATUSES = [
  'AVAILABLE',
  'PERMISSION_DENIED',
  'PERMISSION_DENIED_FOREVER',
  'SERVICE_DISABLED',
  'UNAVAILABLE',
];

/** Tolerancia para relojes de dispositivo adelantados. */
const MAX_CLOCK_SKEW_MS = 10 * 60 * 1000;

/** Campo `metadata` del multipart (§4.3.5). */
const metadataSchema = z
  .object({
    clientUuid: z.uuid('clientUuid debe ser un UUID.'),
    assignmentId: z.uuid('assignmentId debe ser un UUID.'),
    latitude: z.number().min(-90).max(90).nullish(),
    longitude: z.number().min(-180).max(180).nullish(),
    accuracyM: z.number().positive().max(100_000).nullish(),
    locationStatus: z.enum(LOCATION_STATUSES).optional(),
    capturedAt: z.iso.datetime({ offset: true, message: 'capturedAt debe ser ISO 8601 con zona horaria.' }),
    notes: z.string().trim().max(500).default(''),
  })
  .transform((m, ctx) => {
    const hasLat = m.latitude != null;
    const hasLng = m.longitude != null;
    if (hasLat !== hasLng) {
      ctx.addIssue({ code: 'custom', path: ['latitude'], message: 'Latitud y longitud deben enviarse juntas.' });
      return z.NEVER;
    }
    // RB-07: sin coordenadas, el estado explica el motivo; nunca se inventan.
    const locationStatus = m.locationStatus ?? (hasLat ? 'AVAILABLE' : 'UNAVAILABLE');
    if (hasLat !== (locationStatus === 'AVAILABLE')) {
      ctx.addIssue({
        code: 'custom',
        path: ['locationStatus'],
        message: 'locationStatus AVAILABLE requiere coordenadas, y viceversa.',
      });
      return z.NEVER;
    }
    const capturedAt = new Date(m.capturedAt);
    if (capturedAt.getTime() > Date.now() + MAX_CLOCK_SKEW_MS) {
      ctx.addIssue({ code: 'custom', path: ['capturedAt'], message: 'capturedAt está en el futuro.' });
      return z.NEVER;
    }
    return {
      ...m,
      clientUuid: m.clientUuid.toLowerCase(),
      latitude: hasLat ? m.latitude : null,
      longitude: hasLng ? m.longitude : null,
      accuracyM: hasLat ? (m.accuracyM ?? null) : null,
      locationStatus,
      capturedAt,
    };
  });

export const idempotencyKeySchema = z.uuid();

/** Respuesta de recepción; la app Flutter usa `id`, `status` y `receivedAt`. */
const toReceipt = (row) => ({
  id: row.id,
  clientUuid: row.client_uuid,
  assignmentId: row.assignment_id,
  status: row.status,
  capturedAt: row.captured_at,
  receivedAt: row.received_at,
});

function parseMetadata(raw) {
  if (typeof raw !== 'string' || raw.length === 0) {
    throw HttpError.badRequest('Falta el campo "metadata" con los datos de la evidencia.');
  }
  let json;
  try {
    json = JSON.parse(raw);
  } catch {
    throw HttpError.badRequest('El campo "metadata" no es JSON válido.');
  }
  const result = metadataSchema.safeParse(json);
  if (!result.success) {
    throw HttpError.badRequest(
      'Metadatos de evidencia inválidos.',
      result.error.issues.map((i) => ({ field: `metadata.${i.path.join('.')}`, message: i.message })),
    );
  }
  return result.data;
}

/**
 * Resultado de un reintento: misma clave, mismo usuario y misma asignación
 * → se devuelve la evidencia existente sin crear otra (RF-14, RB-10, TC-15).
 * Si la clave pertenece a otro usuario u otra asignación → 409.
 */
async function replayIfExists(user, clientUuid, assignmentId, db = { query }) {
  const { rows } = await db.query('SELECT * FROM evidences WHERE client_uuid = $1', [clientUuid]);
  const existing = rows[0];
  if (!existing) return null;
  if (existing.created_by !== user.id || existing.assignment_id !== assignmentId) {
    throw HttpError.conflict(
      'La clave de idempotencia ya fue usada para otra evidencia.',
      'IDEMPOTENCY_KEY_REUSED',
    );
  }
  return toReceipt(existing);
}

class DuplicateInsert extends Error {}

/**
 * P-06: recepción de evidencia. Devuelve `{ replayed, receipt }`.
 *
 * @param {{ id: string, role: string }} user
 * @param {{ idempotencyKey: string, metadata: unknown,
 *           file?: { path: string, size: number, originalname: string } }} input
 */
export async function receiveEvidence(user, { idempotencyKey, metadata: rawMetadata, file }, { ip } = {}) {
  if (!file) {
    throw new HttpError(400, 'Falta la fotografía en el campo "photo".', 'PHOTO_REQUIRED');
  }
  const metadata = parseMetadata(rawMetadata);
  if (metadata.clientUuid !== idempotencyKey) {
    throw new HttpError(
      400,
      'La cabecera Idempotency-Key debe coincidir con metadata.clientUuid.',
      'IDEMPOTENCY_KEY_MISMATCH',
    );
  }

  // Reintento de una evidencia ya recibida: no se procesa el archivo.
  const replay = await replayIfExists(user, metadata.clientUuid, metadata.assignmentId);
  if (replay) return { replayed: true, receipt: replay };

  // Tipo real del archivo por su firma (TC-17).
  const mime = await detectImageMime(file.path);
  if (!mime) {
    throw new HttpError(415, 'El archivo no es una imagen JPG, PNG o WebP válida.', 'UNSUPPORTED_MEDIA_TYPE');
  }
  const sha256 = await sha256File(file.path);

  let storedPath;
  try {
    const receipt = await withTransaction(async (db) => {
      // RB-04: solo el responsable con asignación vigente (TC-07). Mismo
      // mensaje si no existe o es de otro usuario.
      const { rows } = await db.query(
        `SELECT a.user_id, a.status, ac.id AS activity_id, ac.status AS activity_status,
                e.status AS event_status
           FROM assignments a
           JOIN activities ac ON ac.id = a.activity_id
           JOIN events e ON e.id = ac.event_id
          WHERE a.id = $1`,
        [metadata.assignmentId],
      );
      const assignment = rows[0];
      if (!assignment || assignment.user_id !== user.id || assignment.status !== 'ACTIVE') {
        throw new HttpError(403, 'No tienes una asignación vigente para esta actividad.', 'NOT_ASSIGNED');
      }
      if (!isEventOpen({ status: assignment.event_status })) {
        throw HttpError.conflict('El evento ya no acepta evidencias.', 'EVENT_LOCKED');
      }
      if (assignment.activity_status === 'COMPLETED' || assignment.activity_status === 'CANCELLED') {
        throw HttpError.conflict(`La actividad está ${assignment.activity_status}.`, 'ACTIVITY_LOCKED');
      }

      // Nombre generado por el servidor (§4.3.7).
      const evidenceId = randomUUID();
      storedPath = await storePhoto(file.path, evidenceId, mime);

      const inserted = await db.query(
        `INSERT INTO evidences (id, assignment_id, created_by, client_uuid, photo_path, photo_mime,
                                photo_size_bytes, photo_sha256, latitude, longitude, accuracy_m,
                                location_status, captured_at, notes)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
         ON CONFLICT (client_uuid) DO NOTHING
         RETURNING *`,
        [
          evidenceId,
          metadata.assignmentId,
          user.id,
          metadata.clientUuid,
          storedPath,
          mime,
          file.size,
          sha256,
          metadata.latitude,
          metadata.longitude,
          metadata.accuracyM,
          metadata.locationStatus,
          metadata.capturedAt,
          metadata.notes,
        ],
      );
      // Otro reintento concurrente con la misma clave ganó la carrera.
      if (!inserted.rows[0]) throw new DuplicateInsert();

      await db.query(
        `UPDATE activities SET status = 'SUBMITTED'
          WHERE id = $1 AND status IN ('PENDING', 'IN_PROGRESS')`,
        [assignment.activity_id],
      );
      // Sin coordenadas en la auditoría (§4.3.7).
      await audit(
        {
          actorId: user.id,
          action: 'EVIDENCE_RECEIVED',
          entity: 'evidences',
          entityId: evidenceId,
          metadata: { assignmentId: metadata.assignmentId, locationStatus: metadata.locationStatus },
          ip,
        },
        db,
      );
      return toReceipt(inserted.rows[0]);
    });
    return { replayed: false, receipt };
  } catch (err) {
    // La transacción no se confirmó: el archivo movido no debe quedar huérfano.
    if (storedPath) await removeQuietly(resolveStoredPath(storedPath));
    if (err instanceof DuplicateInsert) {
      const existing = await replayIfExists(user, metadata.clientUuid, metadata.assignmentId);
      return { replayed: true, receipt: existing };
    }
    throw err;
  }
}

// ---------------------------------------------------------------------------
// Consulta
// ---------------------------------------------------------------------------

const EVIDENCE_SELECT = `
  SELECT ev.*, a.activity_id, ac.title AS activity_title, ac.status AS activity_status,
         e.id AS event_id, e.name AS event_name, e.organizer_id,
         e.latitude AS event_latitude, e.longitude AS event_longitude,
         u.full_name AS created_by_name
    FROM evidences ev
    JOIN assignments a ON a.id = ev.assignment_id
    JOIN activities ac ON ac.id = a.activity_id
    JOIN events e ON e.id = ac.event_id
    JOIN users u ON u.id = ev.created_by`;

/** Quién puede ver una evidencia (§4.2.4: acceso restringido). */
function canView(user, row) {
  switch (user.role) {
    case ROLES.ADMIN:
    case ROLES.SUPERVISOR:
      return true;
    case ROLES.ORGANIZER:
      return row.organizer_id === user.id;
    default:
      return row.created_by === user.id;
  }
}

const toEvidence = (row) => ({
  id: row.id,
  clientUuid: row.client_uuid,
  status: row.status,
  assignmentId: row.assignment_id,
  activity: { id: row.activity_id, title: row.activity_title, status: row.activity_status },
  event: { id: row.event_id, name: row.event_name },
  createdBy: { id: row.created_by, fullName: row.created_by_name },
  location: {
    status: row.location_status,
    latitude: row.latitude,
    longitude: row.longitude,
    accuracyM: row.accuracy_m,
    // RB-11: indicador de consistencia, no prueba de presencia.
    distanceToEventM:
      row.latitude != null && row.event_latitude != null
        ? Math.round(haversineMeters(row.latitude, row.longitude, row.event_latitude, row.event_longitude))
        : null,
  },
  photo: {
    url: `/api/v1/evidences/${row.id}/photo`,
    mime: row.photo_mime,
    sizeBytes: row.photo_size_bytes,
    sha256: row.photo_sha256,
  },
  notes: row.notes,
  capturedAt: row.captured_at,
  receivedAt: row.received_at,
});

function haversineMeters(lat1, lon1, lat2, lon2) {
  const R = 6_371_000;
  const rad = (d) => (d * Math.PI) / 180;
  const dLat = rad(lat2 - lat1);
  const dLon = rad(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

async function findViewable(user, id) {
  const { rows } = await query(`${EVIDENCE_SELECT} WHERE ev.id = $1`, [id]);
  const row = rows[0];
  if (!row || !canView(user, row)) throw HttpError.notFound('Evidencia no encontrada.');
  return row;
}

/** GET /evidences/:id con historial de revisiones (RB-09). */
export async function getEvidence(user, id) {
  const row = await findViewable(user, id);
  const reviews = await query(
    `SELECT r.id, r.result, r.comment, r.reviewed_at, u.id AS reviewer_id, u.full_name AS reviewer_name
       FROM reviews r JOIN users u ON u.id = r.reviewer_id
      WHERE r.evidence_id = $1 ORDER BY r.reviewed_at DESC`,
    [id],
  );
  return {
    ...toEvidence(row),
    reviews: reviews.rows.map((r) => ({
      id: r.id,
      result: r.result,
      comment: r.comment,
      reviewedAt: r.reviewed_at,
      reviewer: { id: r.reviewer_id, fullName: r.reviewer_name },
    })),
  };
}

/** Bandeja de revisión (P-07) para supervisor, organizador y administrador. */
export async function listEvidences(user, { eventId, activityId, status, limit, offset }) {
  const where = [];
  const params = [];
  const add = (sql, value) => {
    params.push(value);
    where.push(sql.replace('?', `$${params.length}`));
  };
  if (user.role === ROLES.ORGANIZER) add('e.organizer_id = ?', user.id);
  if (eventId) add('e.id = ?', eventId);
  if (activityId) add('a.activity_id = ?', activityId);
  if (status) add('ev.status = ?', status);
  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';

  const total = await query(
    `SELECT count(*)::int AS n FROM evidences ev
       JOIN assignments a ON a.id = ev.assignment_id
       JOIN activities ac ON ac.id = a.activity_id
       JOIN events e ON e.id = ac.event_id ${whereSql}`,
    params,
  );
  params.push(limit, offset);
  const { rows } = await query(
    `${EVIDENCE_SELECT} ${whereSql}
      ORDER BY ev.received_at DESC, ev.id
      LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params,
  );
  return { items: rows.map(toEvidence), total: total.rows[0].n, limit, offset };
}

/** Archivo de la foto, solo para usuarios autorizados (§4.3.7). */
export async function getPhoto(user, id) {
  const row = await findViewable(user, id);
  return { absolutePath: resolveStoredPath(row.photo_path), mime: row.photo_mime };
}
