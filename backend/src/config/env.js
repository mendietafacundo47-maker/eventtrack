import path from 'node:path';

import dotenv from 'dotenv';
import { z } from 'zod';

dotenv.config({ quiet: true });

const boolString = z
  .enum(['true', 'false', '1', '0', ''])
  .default('false')
  .transform((v) => v === 'true' || v === '1');

const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().positive().default(3000),
  CORS_ORIGINS: z.string().default(''),

  DB_HOST: z.string().min(1),
  DB_PORT: z.coerce.number().int().positive().default(5432),
  DB_USER: z.string().min(1),
  DB_PASSWORD: z.string().min(1),
  DB_NAME: z.string().regex(/^[a-z_][a-z0-9_]*$/, 'Nombre de base de datos no válido'),
  DB_SSL: boolString,

  JWT_SECRET: z.string().min(32, 'JWT_SECRET debe tener al menos 32 caracteres'),
  JWT_EXPIRES_IN: z.string().default('8h'),
  BCRYPT_ROUNDS: z.coerce.number().int().min(10).max(14).default(12),

  UPLOAD_DIR: z.string().min(1).default('uploads'),
  MAX_PHOTO_MB: z.coerce.number().positive().max(25).default(8),
});

const parsed = schema.safeParse(process.env);
if (!parsed.success) {
  // Solo se muestran los nombres de las variables, nunca sus valores.
  const issues = parsed.error.issues
    .map((i) => `  - ${i.path.join('.')}: ${i.message}`)
    .join('\n');
  console.error(`Configuración inválida. Revisa tu archivo .env:\n${issues}`);
  process.exit(1);
}

const env = parsed.data;

export const config = {
  env: env.NODE_ENV,
  isProduction: env.NODE_ENV === 'production',
  port: env.PORT,
  corsOrigins: env.CORS_ORIGINS.split(',').map((o) => o.trim()).filter(Boolean),
  db: {
    host: env.DB_HOST,
    port: env.DB_PORT,
    user: env.DB_USER,
    password: env.DB_PASSWORD,
    database: env.DB_NAME,
    ssl: env.DB_SSL ? { rejectUnauthorized: true } : false,
  },
  jwt: {
    secret: env.JWT_SECRET,
    expiresIn: env.JWT_EXPIRES_IN,
    issuer: 'eventtrack-api',
    audience: 'eventtrack-clients',
  },
  bcryptRounds: env.BCRYPT_ROUNDS,
  uploads: {
    // Fuera de src/ y nunca servido como estático: las fotos solo se entregan
    // mediante un endpoint con autorización (§4.3.7).
    dir: path.resolve(env.UPLOAD_DIR),
    maxPhotoBytes: Math.round(env.MAX_PHOTO_MB * 1024 * 1024),
  },
};
