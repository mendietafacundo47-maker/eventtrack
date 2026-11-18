import { Router } from 'express';
import { z } from 'zod';

import { ALL_ROLES, ROLES } from '../../config/roles.js';
import { authenticate, authorize } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import { PASSWORD_MAX_BYTES, PASSWORD_MIN } from '../../services/password.js';
import * as service from './users.service.js';

export const usersRouter = Router();

// Todo el módulo es exclusivo del administrador (§4.5.4).
usersRouter.use(authenticate, authorize(ROLES.ADMIN));

const password = z
  .string()
  .min(PASSWORD_MIN, `La contraseña debe tener al menos ${PASSWORD_MIN} caracteres.`)
  .refine((p) => Buffer.byteLength(p, 'utf8') <= PASSWORD_MAX_BYTES, 'La contraseña es demasiado larga.')
  .refine((p) => /[A-Za-z]/.test(p) && /\d/.test(p), 'La contraseña debe incluir letras y números.');

const fullName = z.string().trim().min(3).max(120);
const role = z.enum(ALL_ROLES);

const idParams = z.object({ id: z.uuid('Identificador no válido.') });

const listQuery = z.object({
  search: z.string().trim().max(100).optional(),
  role: role.optional(),
  active: z.enum(['true', 'false']).transform((v) => v === 'true').optional(),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  offset: z.coerce.number().int().min(0).default(0),
});

const createBody = z.object({
  fullName,
  email: z.string().trim().toLowerCase().pipe(z.email('Correo electrónico no válido.')),
  role,
  password,
});

const updateBody = z
  .object({
    fullName: fullName.optional(),
    role: role.optional(),
    active: z.boolean().optional(),
    password: password.optional(),
  })
  .strict()
  .refine((b) => Object.keys(b).length > 0, 'No hay cambios para aplicar.');

/** GET /api/v1/users */
usersRouter.get('/', validate(listQuery, 'query'), async (req, res) => {
  res.json(await service.listUsers(req.valid.query));
});

/** GET /api/v1/users/:id */
usersRouter.get('/:id', validate(idParams, 'params'), async (req, res) => {
  res.json(await service.getUser(req.valid.params.id));
});

/** POST /api/v1/users */
usersRouter.post('/', validate(createBody), async (req, res) => {
  const { role: roleCode, ...rest } = req.valid.body;
  const user = await service.createUser({ ...rest, roleCode }, req.user, { ip: req.ip });
  res.status(201).location(`${req.baseUrl}/${user.id}`).json(user);
});

/** PATCH /api/v1/users/:id — actualizar o desactivar (`active: false`). */
usersRouter.patch(
  '/:id',
  validate(idParams, 'params'),
  validate(updateBody),
  async (req, res) => {
    const { role: roleCode, ...rest } = req.valid.body;
    res.json(await service.updateUser(req.valid.params.id, { ...rest, roleCode }, req.user, { ip: req.ip }));
  },
);
