import pino from 'pino';

/**
 * Logs estructurados sin contraseñas, tokens ni datos personales
 * innecesarios (RNF-11).
 */
export const logger = pino({
  level: process.env.LOG_LEVEL ?? (process.env.NODE_ENV === 'test' ? 'silent' : 'info'),
  redact: {
    paths: [
      'req.headers.authorization',
      'req.headers.cookie',
      'req.headers["idempotency-key"]',
      'password',
      '*.password',
      '*.passwordHash',
      '*.password_hash',
      'accessToken',
      '*.accessToken',
    ],
    censor: '[REDACTED]',
  },
});
