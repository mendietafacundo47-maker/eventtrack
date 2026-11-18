# EventTrack

Gestión y control de eventos universitarios con geolocalización GPS y
evidencia fotográfica. Proyecto final de **Optativa IV**, Ingeniería
Informática, Universidad Autónoma Juan Misael Saracho (UAJMS), gestión 2026.

**Equipo:** Elías Rey Aramayo Villena (coordinación y QA) · Alex Mamani Alcoba
(backend y PostgreSQL) · Facundo Mendieta Antelo (Flutter y UI).

## Componentes

| Carpeta | Contenido | Tecnología |
|---|---|---|
| [`eventtrack/`](eventtrack/) | Proyecto `mobile_web_flutter`: app Android del responsable **y** panel web administrativo (un solo proyecto) | Flutter / Dart |
| [`backend/`](backend/) | API REST, autenticación, reglas de negocio, migraciones y almacenamiento de fotografías | Node.js, Express, PostgreSQL |

```
Android (Flutter) ─┐                         ┌─ PostgreSQL (datos)
                   ├─ HTTPS / REST / JSON ──▶ Backend Node.js ─┤
Panel web (Flutter)┘    multipart (fotos)    └─ Almacenamiento de fotografías
```

## Funcionalidades

### App Android (responsable)
- **Pantalla A – Inicio de sesión** con mensaje genérico ante credenciales inválidas (RF-01, TC-02).
- **Pantalla B – Mis actividades**: tarjetas con estado por color y texto, búsqueda y caché sin conexión (RF-08, RF-16).
- **Pantalla C – Registro de evidencia**: foto con cámara o galería (`image_picker`), latitud, longitud y precisión GPS (`geolocator`), observación; avisos claros si se niegan permisos o el GPS está apagado, sin inventar coordenadas (RF-09 a RF-11, RB-06, RB-07).
- **Pantalla D – Sincronización**: cola offline en SQLite (`sqflite`) con estados PENDING, UPLOADING, SYNCED y FAILED, reintentos con backoff exponencial y `client_uuid` para evitar duplicados (RF-12 a RF-14, RB-10).
- La foto se guarda en el almacenamiento privado de la app; SQLite guarda solo la ruta (§4.3.3).

### Panel web (organizador, supervisor, administrador)
- **Resumen** del evento: total de actividades, pendientes, completadas y bandeja de evidencias recientes.
- **Eventos**: crear, editar, activar, cerrar o cancelar; búsqueda, filtros y paginación (RF-05).
- **Actividades y asignaciones**: crear actividades y asignar o quitar responsables (RF-06, RF-07).
- **Evidencias**: foto, coordenadas, precisión, distancia al evento, hora del dispositivo y del servidor; aprobar o rechazar con motivo obligatorio (RF-15, RB-08, RB-09).
- **Usuarios** (solo administrador): crear, cambiar rol, restablecer contraseña, activar o desactivar (RF-03, RF-04).
- **Reportes** por evento: avance, actividades por estado, evidencias revisadas y con GPS (RF-17).

### Backend
- JWT con expiración y revocación al cerrar sesión; contraseñas con bcrypt (RF-02, RNF-01).
- Control de acceso por rol y por recurso en cada endpoint (RF-04, RNF-02).
- `POST /api/v1/evidences` multipart con cabecera `Idempotency-Key`; valida tipo real del archivo, tamaño y asignación (RF-14, TC-15, TC-17, TC-18).
- Migraciones versionadas de las 8 tablas con reversión; auditoría de acciones relevantes (RF-18).
- Helmet, límite de intentos de login, validación con Zod y logs sin datos sensibles (§4.3.7, RNF-11).

## Puesta en marcha rápida

Requisitos: Node.js 20+, PostgreSQL 10+, Flutter 3.47+.

```bash
# 1. Backend
cd backend
npm install
cp .env.example .env        # completar DB_PASSWORD, JWT_SECRET y SEED_ADMIN_PASSWORD
npm run db:create
npm run db:migrate
npm run db:seed             # administrador
npm run db:seed:demo        # usuarios y evento de demostración
npm run dev                 # http://localhost:3000/api/v1

# 2. Panel web (otra terminal)
cd eventtrack
flutter pub get
flutter run -d chrome

# 3. App Android (emulador)
flutter run --dart-define=USE_MOCK_API=false --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1
```

Usuarios de demostración (contraseña `Demo1234`): `organizador@uajms.edu.bo`,
`supervisor@uajms.edu.bo`, `responsable@uajms.edu.bo`. Detalles en
[`backend/README.md`](backend/README.md) y [`eventtrack/README.md`](eventtrack/README.md).

## Pruebas

```bash
cd backend && npm test        # API + PostgreSQL (base eventtrack_test)
cd eventtrack && flutter test # app, cola offline y panel
```

## Seguridad del repositorio

No se suben contraseñas, tokens, `.env`, `node_modules`, compilaciones ni
fotografías de evidencias (`backend/uploads/`). La configuración de ejemplo
está en `backend/.env.example`.
