import { ROLES } from '../../config/roles.js';

/**
 * Condición SQL de visibilidad de eventos según el rol (autorización por
 * recurso, §4.3.7). `alias` es el alias de la tabla `events` en la consulta.
 *
 * - ADMIN y SUPERVISOR: todos los eventos.
 * - ORGANIZER: los eventos que organiza.
 * - RESPONSIBLE: eventos con alguna asignación vigente suya.
 *
 * @returns {{ sql: string, params: unknown[] }} `sql` usa `$${offset+1}`.
 */
export function eventVisibility(user, alias = 'e', offset = 0) {
  switch (user.role) {
    case ROLES.ADMIN:
    case ROLES.SUPERVISOR:
      return { sql: 'TRUE', params: [] };
    case ROLES.ORGANIZER:
      return { sql: `${alias}.organizer_id = $${offset + 1}`, params: [user.id] };
    default:
      return {
        sql: `EXISTS (
          SELECT 1 FROM assignments va JOIN activities vac ON vac.id = va.activity_id
           WHERE vac.event_id = ${alias}.id AND va.user_id = $${offset + 1} AND va.status = 'ACTIVE')`,
        params: [user.id],
      };
  }
}

/** RB-01 / §4.5.4 "Organizador autorizado": dueño del evento o administrador. */
export const canManageEvent = (user, event) =>
  user.role === ROLES.ADMIN || (user.role === ROLES.ORGANIZER && event.organizer_id === user.id);

/** §4.4.7: solo eventos en borrador o activos aceptan cambios operativos. */
export const isEventOpen = (event) => event.status === 'DRAFT' || event.status === 'ACTIVE';
