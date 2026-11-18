// Crea la base de datos DB_NAME si no existe, conectándose a la base
// administrativa `postgres` con las mismas credenciales.
import pg from 'pg';

import { config } from '../src/config/env.js';

const client = new pg.Client({ ...config.db, database: 'postgres' });

try {
  await client.connect();
  const { rowCount } = await client.query(
    'SELECT 1 FROM pg_database WHERE datname = $1',
    [config.db.database],
  );
  if (rowCount > 0) {
    console.log(`La base de datos "${config.db.database}" ya existe.`);
  } else {
    // El nombre está validado por env.js (solo [a-z0-9_]); los identificadores
    // no admiten parámetros en CREATE DATABASE.
    await client.query(`CREATE DATABASE "${config.db.database}" ENCODING 'UTF8'`);
    console.log(`Base de datos "${config.db.database}" creada.`);
  }
} catch (err) {
  console.error(`No se pudo crear la base de datos: ${err.message}`);
  process.exitCode = 1;
} finally {
  await client.end();
}
