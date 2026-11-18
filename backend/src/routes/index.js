import { Router } from 'express';

import { query } from '../config/db.js';
import { authenticate } from '../middleware/auth.js';
import { assignmentsRouter } from '../modules/assignments/assignments.routes.js';
import { myAssignments } from '../modules/assignments/assignments.service.js';
import { authRouter } from '../modules/auth/auth.routes.js';
import { activitiesRouter, eventsRouter } from '../modules/events/events.routes.js';
import { evidencesRouter } from '../modules/evidences/evidences.routes.js';
import { reportsRouter } from '../modules/reports/reports.routes.js';
import { usersRouter } from '../modules/users/users.routes.js';

/** Rutas de /api/v1 (§4.5.4). */
export const apiRouter = Router();

/** Health check: comprueba también la conexión a PostgreSQL. */
apiRouter.get('/health', async (_req, res) => {
  try {
    await query('SELECT 1');
    res.json({ status: 'ok', database: 'ok' });
  } catch {
    res.status(503).json({ status: 'degraded', database: 'unavailable' });
  }
});

apiRouter.use('/auth', authRouter);

/** GET /api/v1/me — perfil y rol del usuario autenticado. */
apiRouter.get('/me', authenticate, (req, res) => {
  const { id, fullName, email, role } = req.user;
  res.json({ id, fullName, email, role });
});

/** GET /api/v1/me/assignments — RF-08, actividades propias (app Android). */
apiRouter.get('/me/assignments', authenticate, async (req, res) => {
  res.json(await myAssignments(req.user));
});

apiRouter.use('/users', usersRouter);
apiRouter.use('/events', eventsRouter);
apiRouter.use('/activities', activitiesRouter);
apiRouter.use('/assignments', assignmentsRouter);
apiRouter.use('/evidences', evidencesRouter);
apiRouter.use('/reports', reportsRouter);
