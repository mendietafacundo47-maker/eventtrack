// Se importa primero en cada archivo de prueba: fija variables antes de que
// src/config/env.js cargue el .env (dotenv no sobrescribe las existentes).
// Las credenciales de PostgreSQL se toman del .env; la base es otra.
import os from 'node:os';
import path from 'node:path';

process.env.NODE_ENV = 'test';
process.env.DB_NAME = process.env.TEST_DB_NAME ?? 'eventtrack_test';
process.env.JWT_SECRET = 'secreto-solo-para-pruebas-automatizadas-0123456789';
process.env.JWT_EXPIRES_IN = '15m';
process.env.BCRYPT_ROUNDS = '10';
process.env.UPLOAD_DIR = path.join(os.tmpdir(), `eventtrack-test-uploads-${process.pid}`);
process.env.MAX_PHOTO_MB = '1';
