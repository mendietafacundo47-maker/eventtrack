import cors from 'cors';
import express from 'express';
import helmet from 'helmet';
import { pinoHttp } from 'pino-http';

import { config } from './config/env.js';
import { logger } from './config/logger.js';
import { errorHandler, notFoundHandler } from './middleware/error-handler.js';
import { apiRouter } from './routes/index.js';

export function createApp() {
  const app = express();

  app.disable('x-powered-by');
  // Detrás de un proxy inverso (HTTPS en producción) para obtener la IP real.
  app.set('trust proxy', config.isProduction ? 1 : false);

  app.use(helmet());
  app.use(
    cors({
      // La app Android no usa CORS; solo aplica al panel web.
      origin: (origin, callback) => {
        // Sin Origin: peticiones de la app Android, curl o el mismo servidor.
        if (!origin || config.corsOrigins.includes(origin)) return callback(null, true);
        // En desarrollo `flutter run -d chrome` usa un puerto aleatorio de localhost.
        const localDev = !config.isProduction && /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin);
        callback(null, localDev);
      },
      methods: ['GET', 'POST', 'PATCH', 'DELETE'],
      allowedHeaders: ['Authorization', 'Content-Type', 'Idempotency-Key'],
    }),
  );
  app.use(
    pinoHttp({
      logger,
      // No registrar cuerpos de petición (pueden contener contraseñas).
      serializers: {
        req: (req) => ({ id: req.id, method: req.method, url: req.url }),
      },
    }),
  );
  app.use(express.json({ limit: '100kb' }));

  app.use('/api/v1', apiRouter);

  app.use(notFoundHandler);
  app.use(errorHandler);
  return app;
}
