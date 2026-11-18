import { query } from '../../config/db.js';

const USER_COLUMNS = `
  u.id, u.full_name, u.email, u.active, u.token_version, u.last_login_at,
  u.created_at, u.updated_at, r.code AS role`;

/** Representación pública: nunca incluye password_hash ni token_version. */
export const toPublicUser = (row) => ({
  id: row.id,
  fullName: row.full_name,
  email: row.email,
  role: row.role,
  active: row.active,
  lastLoginAt: row.last_login_at,
  createdAt: row.created_at,
  updatedAt: row.updated_at,
});

export async function findAuthUserById(id) {
  const { rows } = await query(
    `SELECT u.id, u.full_name, u.email, u.active, u.token_version, r.code AS role
       FROM users u JOIN roles r ON r.id = u.role_id
      WHERE u.id = $1`,
    [id],
  );
  return rows[0] ?? null;
}

export async function findByEmailWithHash(email) {
  const { rows } = await query(
    `SELECT u.id, u.full_name, u.email, u.active, u.token_version,
            u.password_hash, r.code AS role
       FROM users u JOIN roles r ON r.id = u.role_id
      WHERE u.email = $1`,
    [email],
  );
  return rows[0] ?? null;
}

export async function findById(id, db = { query }) {
  const { rows } = await db.query(
    `SELECT ${USER_COLUMNS} FROM users u JOIN roles r ON r.id = u.role_id WHERE u.id = $1`,
    [id],
  );
  return rows[0] ?? null;
}

export async function list({ search, role, active, limit, offset }) {
  const where = [];
  const params = [];
  if (search) {
    // Escapa comodines de LIKE para que se busquen literalmente.
    params.push(`%${search.toLowerCase().replace(/[\\%_]/g, '\\$&')}%`);
    where.push(`(lower(u.full_name) LIKE $${params.length} OR u.email LIKE $${params.length})`);
  }
  if (role) {
    params.push(role);
    where.push(`r.code = $${params.length}`);
  }
  if (active !== undefined) {
    params.push(active);
    where.push(`u.active = $${params.length}`);
  }
  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';

  const total = await query(
    `SELECT count(*)::int AS n FROM users u JOIN roles r ON r.id = u.role_id ${whereSql}`,
    params,
  );
  params.push(limit, offset);
  const { rows } = await query(
    `SELECT ${USER_COLUMNS} FROM users u JOIN roles r ON r.id = u.role_id
      ${whereSql}
      ORDER BY u.full_name, u.id
      LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params,
  );
  return { items: rows, total: total.rows[0].n };
}

export async function insert(db, { roleCode, fullName, email, passwordHash }) {
  const { rows } = await db.query(
    `INSERT INTO users (role_id, full_name, email, password_hash)
     SELECT r.id, $2, $3, $4 FROM roles r WHERE r.code = $1
     RETURNING id`,
    [roleCode, fullName, email, passwordHash],
  );
  return rows[0]?.id ?? null;
}

/**
 * Actualiza solo los campos presentes. `bumpTokenVersion` revoca los tokens
 * emitidos (cambio de contraseña, desactivación o cambio de rol).
 */
export async function update(db, id, { roleCode, fullName, active, passwordHash, bumpTokenVersion }) {
  const sets = [];
  const params = [id];
  const add = (sql, value) => {
    params.push(value);
    sets.push(sql.replace('?', `$${params.length}`));
  };
  if (fullName !== undefined) add('full_name = ?', fullName);
  if (active !== undefined) add('active = ?', active);
  if (passwordHash !== undefined) add('password_hash = ?', passwordHash);
  if (roleCode !== undefined) add('role_id = (SELECT id FROM roles WHERE code = ?)', roleCode);
  if (bumpTokenVersion) sets.push('token_version = token_version + 1');
  if (sets.length === 0) return;
  await db.query(`UPDATE users SET ${sets.join(', ')} WHERE id = $1`, params);
}

export async function touchLastLogin(id) {
  await query('UPDATE users SET last_login_at = now() WHERE id = $1', [id]);
}

export async function revokeTokens(id) {
  await query('UPDATE users SET token_version = token_version + 1 WHERE id = $1', [id]);
}
