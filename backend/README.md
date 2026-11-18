# EventTrack – Backend (Node.js + Express + PostgreSQL)

API REST de EventTrack (informe §4.5.3 y §4.5.4).

## Requisitos

- Node.js 20+ (probado con 24)
- PostgreSQL 10+ con la extensión `pgcrypto` (incluida en el instalador oficial)

## Puesta en marcha

```bash
npm install
cp .env.example .env        # completa DB_PASSWORD, JWT_SECRET y SEED_ADMIN_PASSWORD
npm run db:create           # crea la base DB_NAME si no existe
npm run db:migrate          # aplica migraciones pendientes
npm run db:seed             # crea el administrador definido en SEED_ADMIN_*
npm run db:seed:demo        # (opcional, solo desarrollo) un usuario por rol + evento demo
npm run dev                 # http://localhost:3000/api/v1
```

`.env` nunca se sube al repositorio. Los usuarios demo usan `SEED_DEMO_PASSWORD`:
`organizador@`, `supervisor@` y `responsable@uajms.edu.bo`.

Otros comandos: `npm run db:status` y `node scripts/migrate.js --down` (revierte la
última migración con su archivo `.down.sql`; borra datos).

## Pruebas

```bash
npm test
```

Las pruebas de integración crean y usan la base `eventtrack_test`. No tocan
`eventtrack`, pero sí borran el contenido de `eventtrack_test` en cada ejecución.

## Estructura

```
migrations/      SQL versionado (NNN_nombre.sql + NNN_nombre.down.sql)
scripts/         create-db, migrate, seed
src/
├── config/      env (validado con Zod), db (pool pg), logger (pino), roles
├── middleware/  auth (JWT + RBAC), validate (Zod), error-handler
├── modules/     auth/, users/  (rutas, servicio, repositorio)
├── routes/      montaje de /api/v1
├── services/    password (bcrypt), tokens (JWT), audit
└── app.js / server.js
tests/
```

## Seguridad implementada

| Requisito | Implementación |
|---|---|
| RNF-01 | bcrypt (costo `BCRYPT_ROUNDS`, 12 por defecto); nunca texto plano |
| RF-01 | `POST /auth/login`, mensaje genérico ante cualquier fallo (TC-02) y tiempo constante si el correo no existe |
| RF-02 | JWT HS256 con expiración; `POST /auth/logout` incrementa `token_version` y revoca los tokens del usuario (en todos sus dispositivos) |
| RNF-02 | `authenticate` consulta al usuario en cada petición (cuenta desactivada o rol cambiado surten efecto inmediato) + `authorize(...roles)` |
| §4.3.7 | Rate limit de login (10 fallos / 15 min por IP), Helmet, consultas parametrizadas, validación Zod, errores sin trazas |
| RNF-11 | Logs pino sin cuerpos de petición; cabecera `Authorization` redactada |
| RF-18 | `audit_logs`: LOGIN, LOGIN_FAILED, LOGOUT, USER_CREATED, USER_UPDATED, USER_DEACTIVATED |

Uso de RBAC en nuevas rutas:

```js
router.post('/events', authenticate, authorize(ROLES.ORGANIZER, ROLES.ADMIN), handler);
```

## Endpoints disponibles

| Método y ruta | Acceso |
|---|---|
| `GET /api/v1/health` | Público |
| `POST /api/v1/auth/login` | Público con limitación |
| `POST /api/v1/auth/logout` | Autenticado |
| `GET /api/v1/me` | Autenticado |
| `GET /api/v1/users` (`search`, `role`, `active`, `limit`, `offset`) | Administrador |
| `GET /api/v1/users/:id` | Administrador |
| `POST /api/v1/users` | Administrador |
| `PATCH /api/v1/users/:id` (`fullName`, `role`, `active`, `password`) | Administrador |
| `GET /api/v1/events` (`status`, `search`, `limit`, `offset`) | Autenticado (según visibilidad) |
| `GET /api/v1/events/:id` | Autenticado (según visibilidad) |
| `POST /api/v1/events` | Organizador, administrador |
| `PATCH /api/v1/events/:id` | Organizador del evento, administrador |
| `GET /api/v1/events/:id/activities` | Autenticado (según visibilidad) |
| `POST /api/v1/events/:id/activities` | Organizador del evento, administrador |
| `PATCH /api/v1/activities/:id` | Organizador del evento, administrador |
| `POST /api/v1/assignments` · `DELETE /api/v1/assignments/:id` | Organizador del evento, administrador |
| `GET /api/v1/me/assignments` | Autenticado (sus asignaciones vigentes) |
| `POST /api/v1/evidences` (multipart) | Responsable con asignación vigente |
| `GET /api/v1/evidences` (`eventId`, `activityId`, `status`) | Supervisor, organizador (sus eventos), administrador |
| `GET /api/v1/evidences/:id` · `GET /api/v1/evidences/:id/photo` | Autor, organizador del evento, supervisor, administrador |
| `POST /api/v1/evidences/:id/reviews` | Supervisor, administrador |
| `GET /api/v1/assignments/assignable-users` | Organizador, administrador (responsables activos: id, nombre, correo) |
| `GET /api/v1/reports/events/:id` | Organizador (sus eventos), supervisor, administrador |

Visibilidad de eventos: administrador y supervisor ven todos; el organizador, los
suyos; el responsable, aquellos donde tiene una asignación vigente. Un recurso sin
acceso responde 404, para no revelar que existe.


### Recepción de evidencias (§4.3.5)

```
POST /api/v1/evidences
Authorization: Bearer <token>
Idempotency-Key: <client_uuid>
Content-Type: multipart/form-data

metadata = {"clientUuid","assignmentId","latitude","longitude","accuracyM",
            "locationStatus","capturedAt","notes"}
photo    = archivo JPG / PNG / WebP (máx. MAX_PHOTO_MB)
```

| Respuesta | Caso |
|---|---|
| `201` | Evidencia creada: `{id, clientUuid, assignmentId, status, capturedAt, receivedAt}` |
| `200` + `Idempotent-Replayed: true` | Reintento con la misma clave: devuelve la evidencia existente |
| `400` | Falta la cabecera, no coincide con `clientUuid`, metadatos inválidos (coordenadas fuera de rango, `AVAILABLE` sin coordenadas, fecha futura) o falta la foto |
| `403 NOT_ASSIGNED` | El usuario no tiene una asignación vigente para esa actividad (RB-04) |
| `409` | Clave usada por otro usuario o asignación, actividad completada o cancelada, evento cerrado |
| `413` | Foto mayor que `MAX_PHOTO_MB` |
| `415` | Extensión no permitida, o el contenido no es JPG, PNG ni WebP según su firma real |

Idempotencia (RF-14, RB-10): la clave se compara con `client_uuid UNIQUE` y la
inserción usa `ON CONFLICT DO NOTHING`, así que reintentos simultáneos producen una
sola evidencia. Las fotos se guardan en `UPLOAD_DIR` con nombre generado por el
servidor, junto con su hash SHA-256. Nunca se sirven como archivos estáticos.

### Revisión y estados (RB-12)

- Al recibir evidencia, la actividad pasa de `PENDING`/`IN_PROGRESS` a `SUBMITTED`.
- `APPROVED`: la evidencia y la actividad pasan a `COMPLETED`.
- `REJECTED` (requiere comentario): si no queda otra evidencia pendiente ni aprobada,
  la actividad vuelve a `IN_PROGRESS` para que el responsable reenvíe.
- Cada evidencia se revisa una sola vez (`409 ALREADY_REVIEWED`) y nadie revisa una
  evidencia propia. El organizador también puede marcar la actividad `COMPLETED`
  manualmente mediante `PATCH /activities/:id`.
