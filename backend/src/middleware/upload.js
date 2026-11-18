import { randomUUID } from 'node:crypto';
import path from 'node:path';

import multer from 'multer';

import { config } from '../config/env.js';
import { ALLOWED_EXTENSIONS, TMP_DIR, removeQuietly } from '../services/photo-storage.js';
import { HttpError } from '../utils/http-error.js';

/**
 * Recepción multipart de una evidencia (§4.3.5): campo `metadata` (JSON en
 * texto) y campo `photo` (archivo). El archivo se escribe en un directorio
 * temporal con nombre aleatorio; el servicio lo valida y lo mueve.
 */
const receiver = multer({
  storage: multer.diskStorage({
    destination: TMP_DIR,
    filename: (_req, _file, cb) => cb(null, `${randomUUID()}.upload`),
  }),
  limits: {
    fileSize: config.uploads.maxPhotoBytes,
    files: 1,
    fields: 2,
    fieldSize: 16 * 1024,
    parts: 4,
  },
  // Filtro preliminar por lo declarado; la validación real es por firma.
  fileFilter: (_req, file, cb) => {
    const ext = path.extname(file.originalname ?? '').toLowerCase();
    if (!/^image\/(jpeg|png|webp)$/.test(file.mimetype) || (ext && !ALLOWED_EXTENSIONS.includes(ext))) {
      return cb(new HttpError(415, 'Formato de archivo no permitido. Usa JPG, PNG o WebP.', 'UNSUPPORTED_MEDIA_TYPE'));
    }
    cb(null, true);
  },
}).single('photo');

export function receiveEvidenceUpload(req, res, next) {
  receiver(req, res, (err) => {
    if (!err) return next();
    // Si Multer alcanzó a escribir el archivo antes del error, se elimina.
    removeQuietly(req.file?.path);
    next(err);
  });
}

/**
 * Garantiza que el archivo temporal se elimine al terminar la petición,
 * sea cual sea el resultado (si ya se movió, `rm` no hace nada).
 */
export function cleanupTempUpload(req, res, next) {
  res.on('close', () => removeQuietly(req.file?.path));
  next();
}

export const multerErrorCodes = {
  LIMIT_FILE_SIZE: [413, 'La fotografía supera el tamaño máximo permitido.', 'FILE_TOO_LARGE'],
  LIMIT_FILE_COUNT: [400, 'Solo se permite una fotografía por evidencia.', 'TOO_MANY_FILES'],
  LIMIT_UNEXPECTED_FILE: [400, 'El archivo debe enviarse en el campo "photo".', 'UNEXPECTED_FILE'],
  LIMIT_FIELD_COUNT: [400, 'Demasiados campos en el formulario.', 'TOO_MANY_FIELDS'],
  LIMIT_FIELD_VALUE: [400, 'El campo "metadata" es demasiado grande.', 'FIELD_TOO_LARGE'],
  LIMIT_PART_COUNT: [400, 'Formulario multipart inválido.', 'TOO_MANY_PARTS'],
};

export const isMulterError = (err) => err instanceof multer.MulterError;
