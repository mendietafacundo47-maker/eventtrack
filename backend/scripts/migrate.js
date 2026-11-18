// Migraciones versionadas (§4.5.6, RNF-10).
//
//   npm run db:migrate          aplica las migraciones pendientes
//   npm run db:status           muestra el estado
//   node scripts/migrate.js --down   revierte la última (usa NNN_nombre.down.sql)
//
// Cada archivo `NNN_nombre.sql` se aplica una sola vez dentro de su propia
// transacción. Se guarda un checksum para detectar migraciones ya aplicadas
// que fueron modificadas después (deben crearse migraciones nuevas).
import { createHash } from 'node:crypto';
import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { pool } from '../src/config/db.js';

const dir = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'migrations');
const LOCK_ID = 7_365_001; // pg_advisory_lock: evita ejecuciones concurrentes.

const sha256 = (text) => createHash('sha256').update(text).digest('hex');

async function loadMigrations() {
  const files = (await readdir(dir))
    .filter((f) => /^\d{3}_[\w-]+\.sql$/.test(f) && !f.endsWith('.down.sql'))
    .sort();
  return Promise.all(
    files.map(async (file) => {
      const sql = await readFile(path.join(dir, file), 'utf8');
      return { version: file.slice(0, 3), name: file, sql, checksum: sha256(sql) };
    }),
  );
}

async function main() {
  const mode = process.argv.includes('--down')
    ? 'down'
    : process.argv.includes('--status')
      ? 'status'
      : 'up';

  const client = await pool.connect();
  try {
    await client.query('SELECT pg_advisory_lock($1)', [LOCK_ID]);
    await client.query(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version     varchar(10)  PRIMARY KEY,
        name        varchar(200) NOT NULL,
        checksum    char(64)     NOT NULL,
        applied_at  timestamptz  NOT NULL DEFAULT now()
      )`);

    const migrations = await loadMigrations();
    const { rows } = await client.query(
      'SELECT version, name, checksum, applied_at FROM schema_migrations ORDER BY version',
    );
    const applied = new Map(rows.map((r) => [r.version, r]));

    for (const m of migrations) {
      const a = applied.get(m.version);
      if (a && a.checksum !== m.checksum) {
        throw new Error(
          `La migración ${m.name} ya fue aplicada y su contenido cambió. ` +
            'Crea una nueva migración en lugar de editarla.',
        );
      }
    }

    if (mode === 'status') {
      for (const m of migrations) {
        const a = applied.get(m.version);
        console.log(`${a ? '[x]' : '[ ]'} ${m.name}${a ? `  (${a.applied_at.toISOString()})` : ''}`);
      }
      return;
    }

    if (mode === 'down') {
      const last = rows.at(-1);
      if (!last) {
        console.log('No hay migraciones aplicadas.');
        return;
      }
      const downFile = last.name.replace(/\.sql$/, '.down.sql');
      const sql = await readFile(path.join(dir, downFile), 'utf8');
      await client.query('BEGIN');
      try {
        await client.query(sql);
        await client.query('DELETE FROM schema_migrations WHERE version = $1', [last.version]);
        await client.query('COMMIT');
      } catch (err) {
        await client.query('ROLLBACK');
        throw err;
      }
      console.log(`Revertida: ${last.name}`);
      return;
    }

    const pending = migrations.filter((m) => !applied.has(m.version));
    if (pending.length === 0) {
      console.log('La base de datos está al día.');
      return;
    }
    for (const m of pending) {
      await client.query('BEGIN');
      try {
        await client.query(m.sql);
        await client.query(
          'INSERT INTO schema_migrations (version, name, checksum) VALUES ($1, $2, $3)',
          [m.version, m.name, m.checksum],
        );
        await client.query('COMMIT');
        console.log(`Aplicada: ${m.name}`);
      } catch (err) {
        await client.query('ROLLBACK');
        throw new Error(`Falló ${m.name}: ${err.message}`);
      }
    }
  } finally {
    await client.query('SELECT pg_advisory_unlock($1)', [LOCK_ID]).catch(() => {});
    client.release();
  }
}

try {
  await main();
} catch (err) {
  console.error(err.message);
  process.exitCode = 1;
} finally {
  await pool.end();
}
