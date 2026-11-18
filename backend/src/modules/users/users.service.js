import { withTransaction } from '../../config/db.js';
import { audit } from '../../services/audit.js';
import { hashPassword } from '../../services/password.js';
import { HttpError } from '../../utils/http-error.js';
import * as repo from './users.repository.js';

export async function listUsers(filters) {
  const { items, total } = await repo.list(filters);
  return {
    items: items.map(repo.toPublicUser),
    total,
    limit: filters.limit,
    offset: filters.offset,
  };
}

export async function getUser(id) {
  const row = await repo.findById(id);
  if (!row) throw HttpError.notFound('Usuario no encontrado.');
  return repo.toPublicUser(row);
}

/** RF-03: el administrador crea cuentas (no hay registro público). */
export async function createUser(data, actor, { ip } = {}) {
  const passwordHash = await hashPassword(data.password);
  return withTransaction(async (db) => {
    let id;
    try {
      id = await repo.insert(db, { ...data, passwordHash });
    } catch (err) {
      if (err.code === '23505') {
        throw HttpError.conflict('Ya existe un usuario con ese correo.', 'EMAIL_TAKEN');
      }
      throw err;
    }
    await audit(
      { actorId: actor.id, action: 'USER_CREATED', entity: 'users', entityId: id,
        metadata: { role: data.roleCode }, ip },
      db,
    );
    return repo.toPublicUser(await repo.findById(id, db));
  });
}

/** RF-03: editar, cambiar rol, restablecer contraseña o desactivar. */
export async function updateUser(id, changes, actor, { ip } = {}) {
  if (id === actor.id && (changes.active === false || changes.roleCode !== undefined)) {
    // Evita que el administrador se bloquee a sí mismo.
    throw HttpError.badRequest('No puedes desactivar ni cambiar el rol de tu propia cuenta.');
  }
  const passwordHash =
    changes.password !== undefined ? await hashPassword(changes.password) : undefined;

  return withTransaction(async (db) => {
    const current = await repo.findById(id, db);
    if (!current) throw HttpError.notFound('Usuario no encontrado.');

    const roleChanged = changes.roleCode !== undefined && changes.roleCode !== current.role;
    const deactivated = changes.active === false && current.active;
    await repo.update(db, id, {
      fullName: changes.fullName,
      active: changes.active,
      roleCode: changes.roleCode,
      passwordHash,
      // Cambiar contraseña, rol o desactivar cierra las sesiones abiertas.
      bumpTokenVersion: passwordHash !== undefined || roleChanged || deactivated,
    });

    await audit(
      {
        actorId: actor.id,
        action: deactivated ? 'USER_DEACTIVATED' : 'USER_UPDATED',
        entity: 'users',
        entityId: id,
        metadata: {
          fields: Object.entries(changes)
            .filter(([k, v]) => v !== undefined && k !== 'password')
            .map(([k]) => k),
          passwordReset: passwordHash !== undefined,
        },
        ip,
      },
      db,
    );
    return repo.toPublicUser(await repo.findById(id, db));
  });
}
