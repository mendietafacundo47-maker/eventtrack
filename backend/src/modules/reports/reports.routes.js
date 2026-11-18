import { Router } from 'express';
import { z } from 'zod';

import { ROLES } from '../../config/roles.js';
import { authenticate, authorize } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import { eventReport } from './reports.service.js';

export const reportsRouter = Router();

// §4.5.4: Organizador/Supervisor (y administrador).
reportsRouter.use(authenticate, authorize(ROLES.ORGANIZER, ROLES.SUPERVISOR, ROLES.ADMIN));

const idParams = z.object({ id: z.uuid('Identificador no válido.') });

/** GET /api/v1/reports/events/:id — RF-17. */
reportsRouter.get('/events/:id', validate(idParams, 'params'), async (req, res) => {
  res.json(await eventReport(req.user, req.valid.params.id));
});
