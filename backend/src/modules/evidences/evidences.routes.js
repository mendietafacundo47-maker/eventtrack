import { Router } from 'express';
import { z } from 'zod';

import { ROLES } from '../../config/roles.js';
import { authenticate, authorize } from '../../middleware/auth.js';
import { cleanupTempUpload, receiveEvidenceUpload } from '../../middleware/upload.js';
import { validate } from '../../middleware/validate.js';
import { HttpError } from '../../utils/http-error.js';
import * as evidences from './evidences.service.js';
import { reviewEvidence } from './reviews.service.js';

export const evidencesRouter = Router();

evidencesRouter.use(authenticate);

const idParams = z.object({ id: z.uuid('Identificador no válido.') });

const listQuery = z.object({
  eventId: z.uuid().optional(),
  activityId: z.uuid().optional(),
  status: z.enum(['PENDING_REVIEW', 'APPROVED', 'REJECTED']).optional(),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  offset: z.coerce.number().int().min(0).default(0),
});

const reviewBody = z
  .object({
    result: z.enum(['APPROVED', 'REJECTED']),
    comment: z.string().trim().max(1000).default(''),
  })
  .strict()
  // TC-20: el rechazo exige motivo.
  .refine((b) => b.result === 'APPROVED' || b.comment.length > 0, {
    message: 'Indica el motivo del rechazo.',
    path: ['comment'],
  });

/**
 * La cabecera se valida antes de aceptar el archivo, para no recibir fotos
 * que de todos modos serán rechazadas.
 */
function requireIdempotencyKey(req, _res, next) {
  const raw = req.get('idempotency-key');
  if (!raw) {
    throw new HttpError(400, 'Falta la cabecera Idempotency-Key.', 'IDEMPOTENCY_KEY_REQUIRED');
  }
  const parsed = evidences.idempotencyKeySchema.safeParse(raw.trim());
  if (!parsed.success) {
    throw new HttpError(400, 'Idempotency-Key debe ser un UUID.', 'IDEMPOTENCY_KEY_INVALID');
  }
  req.idempotencyKey = parsed.data.toLowerCase();
  next();
}

/**
 * POST /api/v1/evidences — multipart/form-data (§4.3.5):
 *   Idempotency-Key: <client_uuid>
 *   metadata: JSON { clientUuid, assignmentId, latitude, longitude, accuracyM,
 *                    locationStatus, capturedAt, notes }
 *   photo:    archivo JPG/PNG/WebP
 *
 * 201 si se creó; 200 con `Idempotent-Replayed: true` si ya existía.
 */
evidencesRouter.post(
  '/',
  authorize(ROLES.RESPONSIBLE),
  requireIdempotencyKey,
  cleanupTempUpload,
  receiveEvidenceUpload,
  async (req, res) => {
    const { replayed, receipt } = await evidences.receiveEvidence(
      req.user,
      { idempotencyKey: req.idempotencyKey, metadata: req.body?.metadata, file: req.file },
      { ip: req.ip },
    );
    if (replayed) {
      res.set('Idempotent-Replayed', 'true').status(200);
    } else {
      res.status(201).location(`${req.baseUrl}/${receipt.id}`);
    }
    res.json(receipt);
  },
);

/** GET /api/v1/evidences — bandeja de revisión. */
evidencesRouter.get(
  '/',
  authorize(ROLES.SUPERVISOR, ROLES.ORGANIZER, ROLES.ADMIN),
  validate(listQuery, 'query'),
  async (req, res) => {
    res.json(await evidences.listEvidences(req.user, req.valid.query));
  },
);

/** GET /api/v1/evidences/:id — usuario autorizado. */
evidencesRouter.get('/:id', validate(idParams, 'params'), async (req, res) => {
  res.json(await evidences.getEvidence(req.user, req.valid.params.id));
});

/** GET /api/v1/evidences/:id/photo — archivo protegido por autorización. */
evidencesRouter.get('/:id/photo', validate(idParams, 'params'), async (req, res) => {
  const { absolutePath, mime } = await evidences.getPhoto(req.user, req.valid.params.id);
  res.set({
    'Content-Type': mime,
    'Cache-Control': 'private, no-store',
    'Content-Disposition': 'inline',
  });
  res.sendFile(absolutePath, (err) => {
    if (err && !res.headersSent) {
      res.status(404).json({ message: 'Archivo de evidencia no disponible.', code: 'FILE_MISSING' });
    }
  });
});

/** POST /api/v1/evidences/:id/reviews — RF-15, supervisor. */
evidencesRouter.post(
  '/:id/reviews',
  authorize(ROLES.SUPERVISOR, ROLES.ADMIN),
  validate(idParams, 'params'),
  validate(reviewBody),
  async (req, res) => {
    res.status(201).json(await reviewEvidence(req.user, req.valid.params.id, req.valid.body, { ip: req.ip }));
  },
);
