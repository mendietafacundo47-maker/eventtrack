import { query, withTransaction } from '../../config/db.js';
import { ROLES } from '../../config/roles.js';
import { audit } from '../../services/audit.js';
import { HttpError } from '../../utils/http-error.js';
import { canManageEvent, eventVisibility, isEventOpen } from './event-access.js';

/** Transiciones de estado permitidas (§4.4.7). */
const EVENT_TRANSITIONS = {
  DRAFT: ['ACTIVE', 'CANCELLED'],
  ACTIVE: ['CLOSED', 'CANCELLED'],
  CLOSED: [],
  CANCELLED: [],
};

const EVENT_SELECT = `
  SELECT e.*, u.full_name AS organizer_name,
         (SELECT count(*)::int FROM activities a WHERE a.event_id = e.id) AS activities_total,
         (SELECT count(*)::int FROM activities a
           WHERE a.event_id = e.id AND a.status = 'COMPLETED') AS activities_completed
    FROM events e JOIN users u ON u.id = e.organizer_id`;

export const toEvent = (row) => ({
  id: row.id,
  name: row.name,
  description: row.description,
  locationName: row.location_name,
  startsAt: row.starts_at,
  endsAt: row.ends_at,
  latitude: row.latitude,
  longitude: row.longitude,
  status: row.status,
  organizer: { id: row.organizer_id, fullName: row.organizer_name },
  activities: { total: row.activities_total ?? 0, completed: row.activities_completed ?? 0 },
  createdAt: row.created_at,
  updatedAt: row.updated_at,
});

export async function listEvents(user, { status, search, limit, offset }) {
  const vis = eventVisibility(user);
  const params = [...vis.params];
  const where = [vis.sql];
  if (status) {
    params.push(status);
    where.push(`e.status = $${params.length}`);
  }
  if (search) {
    params.push(`%${search.toLowerCase().replace(/[\\%_]/g, '\\$&')}%`);
    where.push(`lower(e.name) LIKE $${params.length}`);
  }
  const whereSql = where.join(' AND ');

  const total = await query(`SELECT count(*)::int AS n FROM events e WHERE ${whereSql}`, params);
  params.push(limit, offset);
  const { rows } = await query(
    `${EVENT_SELECT} WHERE ${whereSql}
      ORDER BY e.starts_at DESC, e.id
      LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params,
  );
  return { items: rows.map(toEvent), total: total.rows[0].n, limit, offset };
}

/**
 * Evento visible para el usuario. Si no existe o no tiene acceso responde
 * 404 en ambos casos, para no revelar su existencia.
 */
export async function findVisibleEvent(user, id, db = { query }) {
  const vis = eventVisibility(user, 'e', 1);
  const { rows } = await db.query(`${EVENT_SELECT} WHERE e.id = $1 AND ${vis.sql}`, [id, ...vis.params]);
  if (!rows[0]) throw HttpError.notFound('Evento no encontrado.');
  return rows[0];
}

/** Evento que el usuario puede administrar, bloqueado para actualizar. */
export async function findManageableEvent(user, id, db) {
  const event = await findVisibleEvent(user, id, db);
  if (!canManageEvent(user, event)) throw HttpError.forbidden('Solo el organizador del evento puede modificarlo.');
  await db.query('SELECT 1 FROM events WHERE id = $1 FOR UPDATE', [id]);
  return event;
}

async function resolveOrganizer(user, organizerId, db) {
  if (user.role === ROLES.ORGANIZER) {
    if (organizerId && organizerId !== user.id) {
      throw HttpError.forbidden('Un organizador solo puede crear eventos a su nombre.');
    }
    return user.id;
  }
  // Administrador: puede asignar el evento a un organizador activo (RB-01).
  if (!organizerId || organizerId === user.id) return user.id;
  const { rows } = await db.query(
    `SELECT 1 FROM users u JOIN roles r ON r.id = u.role_id
      WHERE u.id = $1 AND u.active AND r.code IN ('ORGANIZER', 'ADMIN')`,
    [organizerId],
  );
  if (!rows[0]) throw HttpError.badRequest('El organizador indicado no existe o no está activo.');
  return organizerId;
}

export async function createEvent(user, data, { ip } = {}) {
  return withTransaction(async (db) => {
    const organizerId = await resolveOrganizer(user, data.organizerId, db);
    const { rows } = await db.query(
      `INSERT INTO events (organizer_id, name, description, location_name, starts_at, ends_at,
                           latitude, longitude, status)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING id`,
      [
        organizerId,
        data.name,
        data.description ?? '',
        data.locationName ?? null,
        data.startsAt,
        data.endsAt,
        data.latitude ?? null,
        data.longitude ?? null,
        data.status ?? 'DRAFT',
      ],
    );
    const id = rows[0].id;
    await audit({ actorId: user.id, action: 'EVENT_CREATED', entity: 'events', entityId: id, ip }, db);
    return toEvent(await findVisibleEvent(user, id, db));
  });
}

export async function updateEvent(user, id, changes, { ip } = {}) {
  return withTransaction(async (db) => {
    const current = await findManageableEvent(user, id, db);
    if (!isEventOpen(current)) {
      throw HttpError.conflict(`El evento está ${current.status} y no admite cambios.`, 'EVENT_LOCKED');
    }
    if (changes.status && changes.status !== current.status) {
      if (!EVENT_TRANSITIONS[current.status].includes(changes.status)) {
        throw HttpError.conflict(
          `Transición no permitida: ${current.status} → ${changes.status}.`,
          'INVALID_TRANSITION',
        );
      }
    }
    const startsAt = changes.startsAt ?? current.starts_at;
    const endsAt = changes.endsAt ?? current.ends_at;
    if (new Date(startsAt) > new Date(endsAt)) {
      throw HttpError.badRequest('La fecha de fin no puede ser anterior a la de inicio.');
    }

    const columns = {
      name: 'name',
      description: 'description',
      locationName: 'location_name',
      startsAt: 'starts_at',
      endsAt: 'ends_at',
      latitude: 'latitude',
      longitude: 'longitude',
      status: 'status',
    };
    const sets = [];
    const params = [id];
    for (const [key, column] of Object.entries(columns)) {
      if (changes[key] !== undefined) {
        params.push(changes[key]);
        sets.push(`${column} = $${params.length}`);
      }
    }
    if (sets.length) await db.query(`UPDATE events SET ${sets.join(', ')} WHERE id = $1`, params);

    await audit(
      {
        actorId: user.id,
        action: changes.status && changes.status !== current.status ? `EVENT_${changes.status}` : 'EVENT_UPDATED',
        entity: 'events',
        entityId: id,
        metadata: { fields: Object.keys(changes) },
        ip,
      },
      db,
    );
    return toEvent(await findVisibleEvent(user, id, db));
  });
}
