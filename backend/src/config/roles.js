/** Códigos de rol (tabla `roles`). Coinciden con `UserRole` en Flutter. */
export const ROLES = Object.freeze({
  ADMIN: 'ADMIN',
  ORGANIZER: 'ORGANIZER',
  SUPERVISOR: 'SUPERVISOR',
  RESPONSIBLE: 'RESPONSIBLE',
});

export const ALL_ROLES = Object.freeze(Object.values(ROLES));
