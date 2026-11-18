import { createApp } from './app.js';
import { pool } from './config/db.js';
import { config } from './config/env.js';
import { logger } from './config/logger.js';

const server = createApp().listen(config.port, () => {
  logger.info(`EventTrack API escuchando en http://localhost:${config.port}/api/v1 (${config.env})`);
});

async function shutdown(signal) {
  logger.info(`${signal} recibido, cerrando servidor...`);
  server.close(async () => {
    await pool.end();
    process.exit(0);
  });
  setTimeout(() => process.exit(1), 10_000).unref();
}

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
