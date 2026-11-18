// Datos iniciales.
//
//   npm run db:seed        crea el administrador definido en SEED_ADMIN_*
//   npm run db:seed:demo   además crea un usuario de prueba por rol (solo desarrollo)
//
// Las contraseñas se leen del .env; nunca se escriben en el código.
import { pool } from '../src/config/db.js';
import { config } from '../src/config/env.js';
import { ROLES } from '../src/config/roles.js';
import { hashPassword, PASSWORD_MIN } from '../src/services/password.js';

const demo = process.argv.includes('--demo');

function required(name) {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Falta ${name} en el archivo .env`);
  return value;
}

async function upsertUser({ email, fullName, role, password }) {
  if (password.length < PASSWORD_MIN) {
    throw new Error(`La contraseña de ${email} debe tener al menos ${PASSWORD_MIN} caracteres.`);
  }
  // No sobrescribe la contraseña de un usuario existente.
  const { rowCount } = await pool.query(
    `INSERT INTO users (role_id, full_name, email, password_hash)
     SELECT r.id, $2, $3, $4 FROM roles r WHERE r.code = $1
     ON CONFLICT (email) DO NOTHING`,
    [role, fullName, email.toLowerCase(), await hashPassword(password)],
  );
  console.log(`${rowCount ? 'Creado ' : 'Ya existe'}  ${role.padEnd(11)} ${email}`);
}

const DEMO_EVENT = 'Evento de demostración EventTrack';

/** Evento activo con actividades asignadas al responsable de prueba. */
async function seedDemoEvent() {
  const exists = await pool.query('SELECT 1 FROM events WHERE name = $1', [DEMO_EVENT]);
  if (exists.rowCount) {
    console.log(`Ya existe  EVENT       ${DEMO_EVENT}`);
    return;
  }
  const ids = await pool.query(
    `SELECT u.email, u.id FROM users u
      WHERE u.email IN ('organizador@uajms.edu.bo', 'responsable@uajms.edu.bo')`,
  );
  const id = Object.fromEntries(ids.rows.map((r) => [r.email, r.id]));
  const organizer = id['organizador@uajms.edu.bo'];
  const responsible = id['responsable@uajms.edu.bo'];

  const day = (offset, hour) => {
    const d = new Date();
    d.setUTCDate(d.getUTCDate() + offset);
    d.setUTCHours(hour, 0, 0, 0);
    return d;
  };
  const event = await pool.query(
    `INSERT INTO events (organizer_id, name, description, location_name, starts_at, ends_at,
                         latitude, longitude, status)
     VALUES ($1, $2, 'Evento de prueba para desarrollo', 'Campus central UAJMS', $3, $4,
             -21.5337, -64.7348, 'ACTIVE')
     RETURNING id`,
    [organizer, DEMO_EVENT, day(-1, 12), day(3, 22)],
  );
  const activities = [
    ['Inspección de Zona A', 'Verificar señalización y ambientes de la zona A.', day(0, 22)],
    ['Registro de Asistencia', 'Habilitar mesas de registro y fotografiar la acreditación.', day(1, 22)],
    ['Montaje de stands', 'Registrar el montaje de stands en el patio central.', day(2, 22)],
  ];
  for (const [title, description, dueAt] of activities) {
    const a = await pool.query(
      `INSERT INTO activities (event_id, title, description, due_at, created_by)
       VALUES ($1, $2, $3, $4, $5) RETURNING id`,
      [event.rows[0].id, title, description, dueAt, organizer],
    );
    await pool.query(
      'INSERT INTO assignments (activity_id, user_id, assigned_by) VALUES ($1, $2, $3)',
      [a.rows[0].id, responsible, organizer],
    );
  }
  console.log(`Creado    EVENT       ${DEMO_EVENT} (${activities.length} actividades asignadas)`);
}

try {
  await upsertUser({
    email: required('SEED_ADMIN_EMAIL'),
    fullName: required('SEED_ADMIN_NAME'),
    role: ROLES.ADMIN,
    password: required('SEED_ADMIN_PASSWORD'),
  });

  if (demo) {
    if (config.isProduction) throw new Error('Los usuarios demo no se crean en producción.');
    const password = required('SEED_DEMO_PASSWORD');
    const demoUsers = [
      ['organizador@uajms.edu.bo', 'Organizador de Prueba', ROLES.ORGANIZER],
      ['supervisor@uajms.edu.bo', 'Supervisor de Prueba', ROLES.SUPERVISOR],
      ['responsable@uajms.edu.bo', 'Responsable de Prueba', ROLES.RESPONSIBLE],
    ];
    for (const [email, fullName, role] of demoUsers) {
      await upsertUser({ email, fullName, role, password });
    }
    await seedDemoEvent();
  }
} catch (err) {
  console.error(err.message);
  process.exitCode = 1;
} finally {
  await pool.end();
}
