import { Router } from 'express';
import { z } from 'zod';

import { ROLES } from '../../config/roles.js';
import { authenticate, authorize } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import * as service from './assignments.service.js';

export const assignmentsRouter = Router();

assignmentsRouter.use(authenticate, authorize(ROLES.ORGANIZER, ROLES.ADMIN));

const createBody = z
  .object({
    activityId: z.uuid('Identificador de actividad no válido.'),
    userId: z.uuid('Identificador de usuario no válido.'),
  })
  .strict();

const idParams = z.object({ id: z.uuid('Identificador no válido.') });

/** GET /api/v1/assignments/assignable-users — responsables activos para asignar. */
assignmentsRouter.get('/assignable-users', async (_req, res) => {
  res.json(await service.assignableUsers());
});

/** POST /api/v1/assignments — RF-07. */
assignmentsRouter.post('/', validate(createBody), async (req, res) => {
  res.status(201).json(await service.assign(req.user, req.valid.body, { ip: req.ip }));
});

/** DELETE /api/v1/assignments/:id — revoca la asignación. */
assignmentsRouter.delete('/:id', validate(idParams, 'params'), async (req, res) => {
  await service.revoke(req.user, req.valid.params.id, { ip: req.ip });
  res.status(204).end();
});
