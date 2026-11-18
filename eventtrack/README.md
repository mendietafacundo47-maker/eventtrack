# EventTrack – Clientes Flutter (Android + panel web)

Un solo proyecto Flutter con dos clientes (informe §4.3.2 y §4.5.5):

- **Android**: app del responsable. Consulta de actividades asignadas y
  registro de evidencias con fotografía, GPS y sincronización offline.
- **Web**: panel administrativo para organizadores, supervisores y
  administradores (eventos, actividades, asignaciones, revisión de
  evidencias, usuarios y reportes).

`lib/main.dart` elige el cliente con una importación condicional
(`lib/bootstrap/bootstrap_mobile.dart` o `bootstrap_web.dart`), así la web
no compila sqflite ni `dart:io`. Esta carpeta (`eventtrack/`) es el proyecto
`mobile_web_flutter` del informe; la API está en `../backend`.

## Requisitos

- Flutter 3.47+ / Dart 3.13+
- Android 7.0 (API 24) o superior
- En Windows: activar **Modo de desarrollador** (`start ms-settings:developers`),
  necesario para compilar con plugins.

## Ejecutar

```bash
flutter pub get

# Con backend simulado (por defecto, mientras la API Node.js no esté lista)
flutter run

# Contra el backend real
flutter run --dart-define=USE_MOCK_API=false \
            --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1
```

Credenciales del modo demostración: `responsable@uajms.edu.bo` / `Demo1234`.
El modo demostración se indica en la interfaz y respeta el modo avión, para
probar el flujo offline. **Sus resultados no sustituyen las pruebas con el
backend real.**

Con el backend real, `npm run db:seed:demo` (en `../backend`) crea
`responsable@uajms.edu.bo` / `Demo1234` con un evento y tres actividades asignadas.

`10.0.2.2` es el PC anfitrión visto desde el emulador. En un teléfono físico usa
la IP del PC en la red Wi-Fi (por ejemplo `http://192.168.1.50:3000/api/v1`) y
permite el puerto 3000 en el Firewall de Windows. El tráfico HTTP sin
cifrar solo está permitido en compilaciones debug; los entornos compartidos y
producción deben usar HTTPS (RNF-03).

## Panel web administrativo

Con el backend en marcha (`npm run dev` en `../backend`):

```bash
flutter run -d chrome          # usa http://localhost:3000/api/v1 por defecto
# o bien
flutter build web              # genera build/web para publicarlo en un servidor
```

El backend acepta en desarrollo cualquier origen `http://localhost:*`; en
producción el dominio del panel debe ir en `CORS_ORIGINS`.

| Rol | Qué ve en el panel |
|---|---|
| Administrador | Todo, incluida la sección Usuarios |
| Organizador | Sus eventos: crear/editar, actividades, asignar responsables, evidencias y reportes |
| Supervisor | Todos los eventos (solo lectura), revisión de evidencias (aprobar / rechazar con motivo) y reportes |
| Responsable | Un aviso para usar la app Android |

Usuarios demo (`npm run db:seed:demo`): `organizador@uajms.edu.bo`,
`supervisor@uajms.edu.bo` y `responsable@uajms.edu.bo`, contraseña `Demo1234`.
El administrador es el definido en `SEED_ADMIN_*` del `.env` del backend.

## Pruebas

```bash
flutter test
```

Prueba de contrato contra el backend real (con el servidor en marcha y datos demo):

```bash
EVENTTRACK_API=http://localhost:3000/api/v1 flutter test test/backend_contract_test.dart
```

Prueba de contrato del panel (crea un evento de prueba, lo recorre de punta a
punta y lo deja cerrado):

```bash
EVENTTRACK_API=http://localhost:3000/api/v1 flutter test test/panel_contract_test.dart
```

Las pruebas de `test/sync_service_test.dart` usan SQLite real en memoria y
cubren TC-12, TC-13, TC-14, TC-15, TC-16 y TC-22 del plan de pruebas, además
de backoff, errores permanentes y sesión expirada.

## Estructura

```
lib/
├── main.dart    elige Android o web (importación condicional)
├── bootstrap/   composición de cada cliente
├── core/        configuración, tema (paleta oficial), errores, red, router, widgets
├── domain/      entidades (app y panel) y contratos
├── data/        SQLite local, almacenamiento seguro, API REST (Dio), mock, repositorios
└── features/
    ├── auth/        Pantalla A (login, compartida) y perfil
    ├── activities/  Pantalla B (Mis actividades) · panel: actividades y asignaciones
    ├── evidence/    Pantalla C (cámara + GPS) · panel: bandeja y revisión
    ├── sync/        Pantalla D y cola de sincronización
    ├── home/        Inicio (Android)
    ├── events/      panel: eventos
    ├── users/       panel: usuarios (administrador)
    ├── reports/     panel: resumen y reportes
    └── panel/       panel: estructura, navegación por rol y componentes
```

## Contrato con el backend

| Método y ruta              | Uso                                             |
|----------------------------|-------------------------------------------------|
| `POST /auth/login`         | `{email, password}` → `{accessToken, user}`     |
| `POST /auth/logout`        | Cierre de sesión                                |
| `GET /me/assignments`      | Asignaciones propias con `activity` y `event`   |
| `POST /evidences`          | Multipart: `metadata` (JSON) + `photo`          |

`POST /evidences` envía la cabecera `Idempotency-Key: <client_uuid>`. Si el
servidor ya procesó ese UUID debe devolver la evidencia existente
(`{id, status, receivedAt}`) con 200/201, no un error.

Clasificación de respuestas en la cola:

- 2xx → `SYNCED`
- sin red, timeout, 408, 429, 5xx → sigue `PENDING`, reintento con backoff exponencial
- 401 → se conserva `PENDING` y se pide iniciar sesión nuevamente
- otros 4xx → `FAILED`, visible al usuario con opción de reintentar o descartar

`metadata` incluye `locationStatus`; si es distinto de `AVAILABLE`, latitud,
longitud y precisión van en `null` (RB-07).
