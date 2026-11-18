import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { mkdir, open, rename, rm } from 'node:fs/promises';
import path from 'node:path';

import { config } from '../config/env.js';

const root = config.uploads.dir;
export const TMP_DIR = path.join(root, 'tmp');

const EXTENSION_BY_MIME = {
  'image/jpeg': '.jpg',
  'image/png': '.png',
  'image/webp': '.webp',
};

export const ALLOWED_EXTENSIONS = Object.freeze(['.jpg', '.jpeg', '.png', '.webp']);

/**
 * MIME real según la firma del archivo (magic bytes), no según lo que
 * declara el cliente (§4.3.7, TC-17). Devuelve `null` si no es una imagen
 * permitida.
 */
export async function detectImageMime(filePath) {
  const fh = await open(filePath, 'r');
  try {
    const buf = Buffer.alloc(12);
    const { bytesRead } = await fh.read(buf, 0, 12, 0);
    if (bytesRead >= 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) {
      return 'image/jpeg';
    }
    if (bytesRead >= 8 && buf.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) {
      return 'image/png';
    }
    if (bytesRead >= 12 && buf.toString('ascii', 0, 4) === 'RIFF' && buf.toString('ascii', 8, 12) === 'WEBP') {
      return 'image/webp';
    }
    return null;
  } finally {
    await fh.close();
  }
}

/** Hash de integridad guardado junto a los metadatos (§4.4.6). */
export function sha256File(filePath) {
  return new Promise((resolve, reject) => {
    const hash = createHash('sha256');
    createReadStream(filePath)
      .on('error', reject)
      .on('data', (chunk) => hash.update(chunk))
      .on('end', () => resolve(hash.digest('hex')));
  });
}

/**
 * Mueve la foto del directorio temporal a su ubicación definitiva con un
 * nombre generado por el servidor. Devuelve la ruta relativa que se guarda en
 * `evidences.photo_path`.
 */
export async function storePhoto(tempPath, evidenceId, mime, now = new Date()) {
  const relative = path.posix.join(
    'evidences',
    String(now.getUTCFullYear()),
    String(now.getUTCMonth() + 1).padStart(2, '0'),
    `${evidenceId}${EXTENSION_BY_MIME[mime]}`,
  );
  const target = resolveStoredPath(relative);
  await mkdir(path.dirname(target), { recursive: true });
  await rename(tempPath, target);
  return relative;
}

/** Ruta absoluta de un archivo guardado, sin permitir salir de `root`. */
export function resolveStoredPath(relative) {
  const absolute = path.resolve(root, relative);
  if (!absolute.startsWith(root + path.sep)) {
    throw new Error('Ruta de archivo fuera del almacenamiento');
  }
  return absolute;
}

export async function removeQuietly(filePath) {
  if (!filePath) return;
  await rm(filePath, { force: true }).catch(() => {});
}
