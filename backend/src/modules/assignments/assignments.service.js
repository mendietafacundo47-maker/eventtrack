import { query, withTransaction } from '../../config/db.js';
import { ROLES } from '../../config/roles.js';
import { audit } from '../../services/audit.js';
import { HttpError } from '../../utils/http-error.js';
import { isEventOpen } from '../events/event-access.js';
import { findManageableActivity } from '../events/activities.service.js';

const toAssignment = (row) => ({
  id: row.id,
  activityId: row.activity_id,
  userId: row.user_id,
  status: row.status,
  assignedAt: row.assigned_at,
  revokedAt: row.revoked_at,
});

/**
 * RF-07, P-02: asignar una actividad a un responsable activo. Si existía
 * una asignación revocada para el mismo par, se reactiva (RB-03).
 */
export async function assign(user, { activityId, userId }, { ip } = {}) {
  return withTransaction(async (db) => {
    const activity = await findManageableActivity(user, activityId, db);
    if (!isEventOpen({ status: activity.event_status })) {
      throw HttpError.conflict('El evento ya no admite asignaciones.', 'EVENT_LOCKED');
    }
    if (activity.status === 'COMPLETED' || activity.status === 'CANCELLED') {
      throw HttpError.conflict(`La actividad está ${activity.status}.`, 'ACTIVITY_LOCKED');
    }

    const target = await db.query(
      `SELECT u.active, r.code AS role FROM users u JOIN roles r ON r.id = u.role_id WHERE u.id = $1`,
      [userId],
    );
    if (!target.rows[0] || !target.rows[0].active || target.rows[0].role !== ROLES.RESPONSIBLE) {
      throw HttpError.badRequest('El usuario indicado no es un responsable activo.');
    }

    const { rows } = await db.query(
      `INSERT INTO assignments (activity_id, user_id, assigned_by)
       VALUES ($1, $2, $3)
       ON CONFLICT (activity_id, user_id) DO UPDATE
          SET status = 'ACTIVE', revoked_at = NULL, assigned_by = EXCLUDED.assigned_by,
              assigned_at = now()
        WHERE assignments.status = 'REVOKED'
       RETURNING *`,
      [activityId, userId, user.id],
    );
    if (!rows[0]) {
      throw HttpError.conflict('El responsable ya está asignado a esta actividad.', 'ALREADY_ASSIGNED');
    }
    await audit(
      { actorId: user.id, action: 'ASSIGNMENT_CREATED', entity: 'assignments', entityId: rows[0].id,
        metadata: { activityId, userId }, ip },
      db,
    );
    return toAssignment(rows[0]);
  });
}

/** Revoca una asignación. Las evidencias ya recibidas se conservan. */
export async function revoke(user, assignmentId, { ip } = {}) {
  return withTransaction(async (db) => {
    const { rows } = await db.query('SELECT activity_id, status FROM assignments WHERE id = $1', [assignmentId]);
    if (!rows[0]) throw HttpError.notFound('Asignación no encontrada.');
    await findManageableActivity(user, rows[0].activity_id, db);
    if (rows[0].status === 'REVOKED') return;
    await db.query(
      `UPDATE assignments SET status = 'REVOKED', revoked_at = now() WHERE id = $1`,
      [assignmentId],
    );
    await audit(
      { actorId: user.id, action: 'ASSIGNMENT_REVOKED', entity: 'assignments', entityId: assignmentId, ip },
      db,
    );
  });
}

/**
 * P-03, RF-08: asignaciones vigentes del usuario autenticado, con los datos
 * de la actividad y del evento. El formato coincide con `AssignmentModel`
 * de la app Flutter.
 */
export async function myAssignments(user) {
  const { rows } = await query(
    `SELECT a.id, a.status, a.assigned_at,
            ac.id AS activity_id, ac.title, ac.description, ac.due_at, ac.status AS activity_status,
            e.id AS event_id, e.name AS event_name, e.latitude, e.longitude,
            e.starts_at, e.ends_at, e.status AS event_status
       FROM assignments a
       JOIN activities ac ON ac.id = a.activity_id
       JOIN events e ON e.id = ac.event_id
      WHERE a.user_id = $1 AND a.status = 'ACTIVE'
        AND e.status IN ('DRAFT', 'ACTIVE')
      ORDER BY ac.due_at NULLS LAST, ac.created_at`,
    [user.id],
  );
  return rows.map((r) => ({
    id: r.id,
    status: r.status,
    assignedAt: r.assigned_at,
    activity: {
      id: r.activity_id,
      title: r.title,
      description: r.description,
      dueAt: r.due_at,
      status: r.activity_status,
    },
    event: {
      id: r.event_id,
      name: r.event_name,
      latitude: r.latitude,
      longitude: r.longitude,
      startsAt: r.starts_at,
      endsAt: r.ends_at,
      status: r.event_status,
    },
  }));
}

/**
 * Responsables activos que se pueden asignar (RF-07). Solo datos mínimos:
 * el organizador no necesita el módulo completo de usuarios.
 */
export async function assignableUsers() {
  const { rows } = await query(
    `SELECT u.id, u.full_name, u.email
       FROM users u JOIN roles r ON r.id = u.role_id
      WHERE r.code = 'RESPONSIBLE' AND u.active
      ORDER BY u.full_name`,
  );
  return rows.map((r) => ({ id: r.id, fullName: r.full_name, email: r.email }));
}
