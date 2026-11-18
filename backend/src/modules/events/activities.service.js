import { query, withTransaction } from '../../config/db.js';
import { audit } from '../../services/audit.js';
import { HttpError } from '../../utils/http-error.js';
import { canManageEvent, isEventOpen } from './event-access.js';
import { findManageableEvent, findVisibleEvent } from './events.service.js';

const ACTIVITY_SELECT = `
  SELECT ac.*,
         COALESCE((
           SELECT json_agg(json_build_object(
                    'assignmentId', a.id, 'userId', u.id, 'fullName', u.full_name,
                    'status', a.status, 'assignedAt', a.assigned_at)
                  ORDER BY u.full_name)
             FROM assignments a JOIN users u ON u.id = a.user_id
            WHERE a.activity_id = ac.id AND a.status = 'ACTIVE'), '[]'::json) AS responsibles,
         (SELECT count(*)::int FROM evidences ev JOIN assignments a ON a.id = ev.assignment_id
           WHERE a.activity_id = ac.id) AS evidences_total
    FROM activities ac`;

export const toActivity = (row) => ({
  id: row.id,
  eventId: row.event_id,
  title: row.title,
  description: row.description,
  dueAt: row.due_at,
  status: row.status,
  responsibles: row.responsibles ?? [],
  evidencesTotal: row.evidences_total ?? 0,
  createdAt: row.created_at,
  updatedAt: row.updated_at,
});

/** Actividades de un evento visible para el usuario. */
export async function listActivities(user, eventId) {
  await findVisibleEvent(user, eventId);
  const { rows } = await query(
    `${ACTIVITY_SELECT} WHERE ac.event_id = $1 ORDER BY ac.due_at NULLS LAST, ac.created_at`,
    [eventId],
  );
  return rows.map(toActivity);
}

/** RF-06, P-02: el organizador crea actividades en su evento. */
export async function createActivity(user, eventId, data, { ip } = {}) {
  return withTransaction(async (db) => {
    const event = await findManageableEvent(user, eventId, db);
    if (!isEventOpen(event)) {
      throw HttpError.conflict(
        `El evento está ${event.status} y no acepta nuevas actividades.`,
        'EVENT_LOCKED',
      );
    }
    const { rows } = await db.query(
      `INSERT INTO activities (event_id, title, description, due_at, created_by)
       VALUES ($1, $2, $3, $4, $5) RETURNING id`,
      [eventId, data.title, data.description ?? '', data.dueAt ?? null, user.id],
    );
    const id = rows[0].id;
    await audit(
      { actorId: user.id, action: 'ACTIVITY_CREATED', entity: 'activities', entityId: id,
        metadata: { eventId }, ip },
      db,
    );
    const created = await db.query(`${ACTIVITY_SELECT} WHERE ac.id = $1`, [id]);
    return toActivity(created.rows[0]);
  });
}

/** Actividad + su evento, bloqueada para actualizar, si el usuario la administra. */
export async function findManageableActivity(user, activityId, db) {
  const { rows } = await db.query(
    `SELECT ac.*, e.organizer_id, e.status AS event_status
       FROM activities ac JOIN events e ON e.id = ac.event_id
      WHERE ac.id = $1
        FOR UPDATE OF ac`,
    [activityId],
  );
  const activity = rows[0];
  if (!activity || !canManageEvent(user, { organizer_id: activity.organizer_id })) {
    throw HttpError.notFound('Actividad no encontrada.');
  }
  return activity;
}

/**
 * RF-06: editar actividad. El organizador puede cancelarla o marcarla como
 * completada manualmente si así lo define su política (RB-12).
 */
export async function updateActivity(user, activityId, changes, { ip } = {}) {
  return withTransaction(async (db) => {
    const current = await findManageableActivity(user, activityId, db);
    if (!isEventOpen({ status: current.event_status })) {
      throw HttpError.conflict('El evento ya no admite cambios.', 'EVENT_LOCKED');
    }
    if (current.status === 'CANCELLED') {
      throw HttpError.conflict('La actividad está cancelada.', 'ACTIVITY_LOCKED');
    }
    const columns = { title: 'title', description: 'description', dueAt: 'due_at', status: 'status' };
    const sets = [];
    const params = [activityId];
    for (const [key, column] of Object.entries(columns)) {
      if (changes[key] !== undefined) {
        params.push(changes[key]);
        sets.push(`${column} = $${params.length}`);
      }
    }
    if (sets.length) await db.query(`UPDATE activities SET ${sets.join(', ')} WHERE id = $1`, params);
    await audit(
      { actorId: user.id, action: 'ACTIVITY_UPDATED', entity: 'activities', entityId: activityId,
        metadata: { fields: Object.keys(changes), status: changes.status }, ip },
      db,
    );
    const updated = await db.query(`${ACTIVITY_SELECT} WHERE ac.id = $1`, [activityId]);
    return toActivity(updated.rows[0]);
  });
}
