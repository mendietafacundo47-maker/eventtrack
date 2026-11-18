import bcrypt from 'bcryptjs';

import { config } from '../config/env.js';

// bcrypt solo considera los primeros 72 bytes de la contraseña.
export const PASSWORD_MIN = 8;
export const PASSWORD_MAX_BYTES = 72;

/** Hash bcrypt con el costo configurado (RNF-01). */
export const hashPassword = (plain) => bcrypt.hash(plain, config.bcryptRounds);

export const verifyPassword = (plain, hash) => bcrypt.compare(plain, hash);

// Hash de una contraseña aleatoria: se compara contra él cuando el usuario no
// existe, para que el tiempo de respuesta no revele si el correo está
// registrado (TC-02).
let dummyHash;
export async function verifyAgainstDummy(plain) {
  dummyHash ??= await bcrypt.hash(crypto.randomUUID(), config.bcryptRounds);
  await bcrypt.compare(plain, dummyHash);
  return false;
}
