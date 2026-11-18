import { logger } from '../config/logger.js';
import { query } from '../config/db.js';

/**
 * Registra una acción relevante (RF-18). `metadata` nunca debe contener
 * contraseñas, tokens ni coordenadas completas (RNF-11, §4.3.7).
 *
 * @param {{ actorId?: string|null, action: string, entity: string,
 *           entityId?: string|null, metadata?: object, ip?: string|null }} entry
 * @param {{ query: Function }} [db] cliente de una transacción en curso
 */
export async function audit(entry, db = { query }) {
  try {
    await db.query(
      `INSERT INTO audit_logs (actor_id, action, entity, entity_id, metadata, ip)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [
        entry.actorId ?? null,
        entry.action,
        entry.entity,
        entry.entityId ?? null,
        JSON.stringify(entry.metadata ?? {}),
        entry.ip ?? null,
      ],
    );
  } catch (err) {
    // Dentro de una transacción el error debe propagarse para hacer rollback.
    if (db.query !== query) throw err;
    logger.error({ err, action: entry.action }, 'No se pudo registrar la auditoría');
  }
}
