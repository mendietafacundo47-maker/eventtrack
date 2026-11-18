import { withTransaction } from '../../config/db.js';
import { audit } from '../../services/audit.js';
import { HttpError } from '../../utils/http-error.js';

/**
 * P-07, RF-15: el supervisor aprueba o rechaza una evidencia.
 *
 * Política de cierre de actividad (RB-12, §4.4.7):
 * - APPROVED → la actividad pasa a COMPLETED.
 * - REJECTED → si no queda otra evidencia pendiente ni aprobada, la
 *   actividad vuelve a IN_PROGRESS para que el responsable reenvíe.
 *
 * Cada revisión queda en `reviews` (RB-09); una evidencia solo se revisa una
 * vez para evitar decisiones contradictorias entre supervisores.
 */
export async function reviewEvidence(user, evidenceId, { result, comment }, { ip } = {}) {
  return withTransaction(async (db) => {
    const { rows } = await db.query(
      `SELECT ev.id, ev.status, ev.created_by, a.activity_id
         FROM evidences ev JOIN assignments a ON a.id = ev.assignment_id
        WHERE ev.id = $1
          FOR UPDATE OF ev`,
      [evidenceId],
    );
    const evidence = rows[0];
    if (!evidence) throw HttpError.notFound('Evidencia no encontrada.');
    if (evidence.created_by === user.id) {
      throw HttpError.forbidden('No puedes revisar una evidencia que registraste tú.');
    }
    if (evidence.status !== 'PENDING_REVIEW') {
      throw HttpError.conflict(`La evidencia ya fue revisada (${evidence.status}).`, 'ALREADY_REVIEWED');
    }

    // Bloquea la actividad para que dos revisiones simultáneas de evidencias
    // distintas no dejen un estado inconsistente.
    await db.query('SELECT 1 FROM activities WHERE id = $1 FOR UPDATE', [evidence.activity_id]);

    const review = await db.query(
      `INSERT INTO reviews (evidence_id, reviewer_id, result, comment)
       VALUES ($1, $2, $3, $4) RETURNING id, result, comment, reviewed_at`,
      [evidenceId, user.id, result, comment],
    );
    await db.query('UPDATE evidences SET status = $2 WHERE id = $1', [evidenceId, result]);

    if (result === 'APPROVED') {
      await db.query(
        `UPDATE activities SET status = 'COMPLETED' WHERE id = $1 AND status <> 'CANCELLED'`,
        [evidence.activity_id],
      );
    } else {
      await db.query(
        `UPDATE activities ac SET status = 'IN_PROGRESS'
          WHERE ac.id = $1 AND ac.status = 'SUBMITTED'
            AND NOT EXISTS (
              SELECT 1 FROM evidences ev JOIN assignments a ON a.id = ev.assignment_id
               WHERE a.activity_id = ac.id AND ev.status IN ('PENDING_REVIEW', 'APPROVED'))`,
        [evidence.activity_id],
      );
    }
    const activity = await db.query('SELECT id, status FROM activities WHERE id = $1', [evidence.activity_id]);

    await audit(
      {
        actorId: user.id,
        action: `EVIDENCE_${result}`,
        entity: 'evidences',
        entityId: evidenceId,
        metadata: { reviewId: review.rows[0].id },
        ip,
      },
      db,
    );

    const r = review.rows[0];
    return {
      review: {
        id: r.id,
        result: r.result,
        comment: r.comment,
        reviewedAt: r.reviewed_at,
        reviewer: { id: user.id, fullName: user.fullName },
      },
      evidence: { id: evidenceId, status: result },
      activity: activity.rows[0],
    };
  });
}
