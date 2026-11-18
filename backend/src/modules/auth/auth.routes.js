import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { z } from 'zod';

import { config } from '../../config/env.js';
import { authenticate } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import * as auth from './auth.service.js';

export const authRouter = Router();

// Protección contra fuerza bruta: solo cuentan los intentos fallidos (§4.3.7).
const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: config.env === 'test' ? 1000 : 10,
  skipSuccessfulRequests: true,
  standardHeaders: 'draft-8',
  legacyHeaders: false,
  message: {
    message: 'Demasiados intentos fallidos. Espera unos minutos e inténtalo de nuevo.',
    code: 'TOO_MANY_ATTEMPTS',
  },
});

const loginSchema = z.object({
  email: z.string().trim().toLowerCase().pipe(z.email('Correo electrónico no válido.')),
  password: z.string().min(1, 'Ingresa tu contraseña.').max(200),
});

/** POST /api/v1/auth/login — público con limitación. */
authRouter.post('/login', loginLimiter, validate(loginSchema), async (req, res) => {
  res.json(await auth.login(req.valid.body, { ip: req.ip }));
});

/** POST /api/v1/auth/logout — autenticado. */
authRouter.post('/logout', authenticate, async (req, res) => {
  await auth.logout(req.user, { ip: req.ip });
  res.status(204).end();
});
