import { query } from '../../config/db.js';
import { findVisibleEvent, toEvent } from '../events/events.service.js';

const ACTIVITY_STATUSES = ['PENDING', 'IN_PROGRESS', 'SUBMITTED', 'COMPLETED', 'CANCELLED'];

/**
 * RF-17 / P-08: indicadores de un evento calculados directamente de los
 * registros (TC-21: los totales deben coincidir con la base de datos).
 */
export async function eventReport(user, eventId) {
  const event = await findVisibleEvent(user, eventId);

  const { rows } = await query(
    `SELECT ac.id, ac.title, ac.status, ac.due_at,
            COALESCE((SELECT json_agg(u.full_name ORDER BY u.full_name)
                        FROM assignments a JOIN users u ON u.id = a.user_id
                       WHERE a.activity_id = ac.id AND a.status = 'ACTIVE'), '[]'::json) AS responsibles,
            count(ev.id)::int AS evidences_total,
            count(ev.id) FILTER (WHERE ev.status = 'PENDING_REVIEW')::int AS pending_review,
            count(ev.id) FILTER (WHERE ev.status = 'APPROVED')::int AS approved,
            count(ev.id) FILTER (WHERE ev.status = 'REJECTED')::int AS rejected,
            count(ev.id) FILTER (WHERE ev.latitude IS NOT NULL)::int AS with_location,
            max(ev.received_at) AS last_evidence_at
       FROM activities ac
       LEFT JOIN assignments asg ON asg.activity_id = ac.id
       LEFT JOIN evidences ev ON ev.assignment_id = asg.id
      WHERE ac.event_id = $1
      GROUP BY ac.id
      ORDER BY ac.due_at NULLS LAST, ac.created_at`,
    [eventId],
  );

  const extra = await query(
    `SELECT
       (SELECT count(*)::int FROM assignments a JOIN activities ac ON ac.id = a.activity_id
         WHERE ac.event_id = $1 AND a.status = 'ACTIVE') AS assignments_active,
       (SELECT count(*)::int FROM reviews r
          JOIN evidences ev ON ev.id = r.evidence_id
          JOIN assignments a ON a.id = ev.assignment_id
          JOIN activities ac ON ac.id = a.activity_id
         WHERE ac.event_id = $1) AS reviews_total`,
    [eventId],
  );

  const byStatus = Object.fromEntries(ACTIVITY_STATUSES.map((s) => [s, 0]));
  const evidences = { total: 0, pendingReview: 0, approved: 0, rejected: 0, withLocation: 0, withoutLocation: 0 };
  for (const r of rows) {
    byStatus[r.status] += 1;
    evidences.total += r.evidences_total;
    evidences.pendingReview += r.pending_review;
    evidences.approved += r.approved;
    evidences.rejected += r.rejected;
    evidences.withLocation += r.with_location;
  }
  evidences.withoutLocation = evidences.total - evidences.withLocation;

  // Las canceladas no cuentan para el avance.
  const countable = rows.length - byStatus.CANCELLED;
  const completionRate = countable > 0 ? Math.round((byStatus.COMPLETED / countable) * 1000) / 10 : 0;

  return {
    event: toEvent(event),
    activities: {
      total: rows.length,
      // "Pendientes" del panel: todo lo que aún no está completado ni cancelado.
      open: rows.length - byStatus.COMPLETED - byStatus.CANCELLED,
      byStatus,
    },
    assignments: { active: extra.rows[0].assignments_active },
    evidences,
    reviews: { total: extra.rows[0].reviews_total },
    completionRate,
    items: rows.map((r) => ({
      id: r.id,
      title: r.title,
      status: r.status,
      dueAt: r.due_at,
      responsibles: r.responsibles,
      evidences: {
        total: r.evidences_total,
        pendingReview: r.pending_review,
        approved: r.approved,
        rejected: r.rejected,
      },
      lastEvidenceAt: r.last_evidence_at,
    })),
    generatedAt: new Date().toISOString(),
  };
}
