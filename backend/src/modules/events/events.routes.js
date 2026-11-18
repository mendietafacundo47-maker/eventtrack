import { Router } from 'express';
import { z } from 'zod';

import { ROLES } from '../../config/roles.js';
import { authenticate, authorize } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import * as activities from './activities.service.js';
import * as events from './events.service.js';

export const eventsRouter = Router();
export const activitiesRouter = Router();

eventsRouter.use(authenticate);
activitiesRouter.use(authenticate);

const managers = authorize(ROLES.ORGANIZER, ROLES.ADMIN);

const isoDate = z.iso
  .datetime({ offset: true, message: 'Fecha inválida; usa ISO 8601 con zona horaria.' })
  .transform((s) => new Date(s));
const latitude = z.number().min(-90).max(90);
const longitude = z.number().min(-180).max(180);
const coordsTogether = (b) => (b.latitude === undefined) === (b.longitude === undefined);
const coordsMessage = { message: 'Latitud y longitud deben enviarse juntas.', path: ['latitude'] };

const idParams = z.object({ id: z.uuid('Identificador no válido.') });

const listQuery = z.object({
  status: z.enum(['DRAFT', 'ACTIVE', 'CLOSED', 'CANCELLED']).optional(),
  search: z.string().trim().max(100).optional(),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  offset: z.coerce.number().int().min(0).default(0),
});

const eventFields = {
  name: z.string().trim().min(3).max(160),
  description: z.string().trim().max(5000),
  locationName: z.string().trim().max(200).nullable(),
  startsAt: isoDate,
  endsAt: isoDate,
  latitude: latitude.nullable(),
  longitude: longitude.nullable(),
};

const createEventBody = z
  .object({
    ...eventFields,
    description: eventFields.description.optional(),
    locationName: eventFields.locationName.optional(),
    latitude: eventFields.latitude.optional(),
    longitude: eventFields.longitude.optional(),
    status: z.enum(['DRAFT', 'ACTIVE']).optional(),
    organizerId: z.uuid().optional(),
  })
  .strict()
  .refine((b) => b.startsAt <= b.endsAt, {
    message: 'La fecha de fin no puede ser anterior a la de inicio.',
    path: ['endsAt'],
  })
  .refine(coordsTogether, coordsMessage);

const updateEventBody = z
  .object({
    ...Object.fromEntries(Object.entries(eventFields).map(([k, v]) => [k, v.optional()])),
    status: z.enum(['DRAFT', 'ACTIVE', 'CLOSED', 'CANCELLED']).optional(),
  })
  .strict()
  .refine((b) => Object.keys(b).length > 0, 'No hay cambios para aplicar.')
  .refine(coordsTogether, coordsMessage);

const createActivityBody = z
  .object({
    title: z.string().trim().min(3).max(160),
    description: z.string().trim().max(5000).optional(),
    dueAt: isoDate.optional(),
  })
  .strict();

const updateActivityBody = z
  .object({
    title: z.string().trim().min(3).max(160).optional(),
    description: z.string().trim().max(5000).optional(),
    dueAt: isoDate.nullable().optional(),
    // SUBMITTED lo asigna el sistema al recibir evidencia.
    status: z.enum(['PENDING', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED']).optional(),
  })
  .strict()
  .refine((b) => Object.keys(b).length > 0, 'No hay cambios para aplicar.');

/** GET /api/v1/events — eventos autorizados para el usuario. */
eventsRouter.get('/', validate(listQuery, 'query'), async (req, res) => {
  res.json(await events.listEvents(req.user, req.valid.query));
});

/** GET /api/v1/events/:id */
eventsRouter.get('/:id', validate(idParams, 'params'), async (req, res) => {
  res.json(events.toEvent(await events.findVisibleEvent(req.user, req.valid.params.id)));
});

/** POST /api/v1/events — RF-05, P-01. */
eventsRouter.post('/', managers, validate(createEventBody), async (req, res) => {
  const event = await events.createEvent(req.user, req.valid.body, { ip: req.ip });
  res.status(201).location(`${req.baseUrl}/${event.id}`).json(event);
});

/** PATCH /api/v1/events/:id — organizador del evento o administrador. */
eventsRouter.patch('/:id', managers, validate(idParams, 'params'), validate(updateEventBody), async (req, res) => {
  res.json(await events.updateEvent(req.user, req.valid.params.id, req.valid.body, { ip: req.ip }));
});

/** GET /api/v1/events/:id/activities */
eventsRouter.get('/:id/activities', validate(idParams, 'params'), async (req, res) => {
  res.json(await activities.listActivities(req.user, req.valid.params.id));
});

/** POST /api/v1/events/:id/activities — RF-06, P-02. */
eventsRouter.post(
  '/:id/activities',
  managers,
  validate(idParams, 'params'),
  validate(createActivityBody),
  async (req, res) => {
    const activity = await activities.createActivity(req.user, req.valid.params.id, req.valid.body, { ip: req.ip });
    res.status(201).json(activity);
  },
);

/** PATCH /api/v1/activities/:id — RF-06. */
activitiesRouter.patch(
  '/:id',
  managers,
  validate(idParams, 'params'),
  validate(updateActivityBody),
  async (req, res) => {
    res.json(await activities.updateActivity(req.user, req.valid.params.id, req.valid.body, { ip: req.ip }));
  },
);
