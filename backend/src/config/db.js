import pg from 'pg';

import { config } from './env.js';
import { logger } from './logger.js';

// Devolver NUMERIC (coordenadas, precisión) como número en lugar de string.
pg.types.setTypeParser(pg.types.builtins.NUMERIC, (v) => (v === null ? null : Number(v)));

export const pool = new pg.Pool({
  ...config.db,
  max: 10,
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 5_000,
});

pool.on('error', (err) => {
  logger.error({ err }, 'Error inesperado en una conexión inactiva de PostgreSQL');
});

/**
 * Consulta parametrizada. Nunca concatenar valores en `text` (§4.3.7).
 * @param {string} text
 * @param {unknown[]} [params]
 */
export const query = (text, params) => pool.query(text, params);

/**
 * Ejecuta `fn` dentro de una transacción; hace ROLLBACK si lanza un error.
 * @template T
 * @param {(client: pg.PoolClient) => Promise<T>} fn
 * @returns {Promise<T>}
 */
export async function withTransaction(fn) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}
