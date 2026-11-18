-- EventTrack · Migración 001 · Esquema inicial (informe §4.4.6, §4.4.7)
-- Compatible con PostgreSQL 10+. Todos los timestamps se guardan en UTC
-- (timestamptz) y los identificadores públicos son UUID.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Mantiene updated_at al día en las tablas que lo tienen.
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- roles
-- ---------------------------------------------------------------------------
CREATE TABLE roles (
  id    smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code  varchar(30)  NOT NULL UNIQUE,
  name  varchar(60)  NOT NULL UNIQUE
);

INSERT INTO roles (code, name) VALUES
  ('ADMIN',       'Administrador'),
  ('ORGANIZER',   'Organizador'),
  ('SUPERVISOR',  'Supervisor'),
  ('RESPONSIBLE', 'Responsable');

-- ---------------------------------------------------------------------------
-- users
-- ---------------------------------------------------------------------------
CREATE TABLE users (
  id             uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  role_id        smallint     NOT NULL REFERENCES roles (id),
  full_name      varchar(120) NOT NULL CHECK (length(trim(full_name)) > 0),
  email          varchar(254) NOT NULL CHECK (email = lower(email) AND email LIKE '%_@_%'),
  -- Hash bcrypt; nunca texto plano (RNF-01).
  password_hash  varchar(100) NOT NULL,
  active         boolean      NOT NULL DEFAULT true,
  -- Se incrementa al cerrar sesión, cambiar contraseña o desactivar la
  -- cuenta: invalida todos los tokens emitidos antes.
  token_version  integer      NOT NULL DEFAULT 0,
  last_login_at  timestamptz,
  created_at     timestamptz  NOT NULL DEFAULT now(),
  updated_at     timestamptz  NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX users_email_uq ON users (email);
CREATE INDEX users_role_idx ON users (role_id);
CREATE TRIGGER users_updated_at BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE PROCEDURE set_updated_at();

-- ---------------------------------------------------------------------------
-- events
-- ---------------------------------------------------------------------------
CREATE TABLE events (
  id            uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  -- RB-01: todo evento tiene un organizador responsable.
  organizer_id  uuid         NOT NULL REFERENCES users (id),
  name          varchar(160) NOT NULL CHECK (length(trim(name)) > 0),
  description   text         NOT NULL DEFAULT '',
  location_name varchar(200),
  starts_at     timestamptz  NOT NULL,
  ends_at       timestamptz  NOT NULL,
  latitude      numeric(9,6) CHECK (latitude  BETWEEN -90  AND 90),
  longitude     numeric(9,6) CHECK (longitude BETWEEN -180 AND 180),
  status        varchar(20)  NOT NULL DEFAULT 'DRAFT'
                CHECK (status IN ('DRAFT', 'ACTIVE', 'CLOSED', 'CANCELLED')),
  created_at    timestamptz  NOT NULL DEFAULT now(),
  updated_at    timestamptz  NOT NULL DEFAULT now(),
  CONSTRAINT events_dates_chk CHECK (starts_at <= ends_at),
  CONSTRAINT events_coords_pair_chk CHECK ((latitude IS NULL) = (longitude IS NULL))
);
CREATE INDEX events_organizer_idx ON events (organizer_id);
CREATE INDEX events_status_start_idx ON events (status, starts_at);
CREATE TRIGGER events_updated_at BEFORE UPDATE ON events
  FOR EACH ROW EXECUTE PROCEDURE set_updated_at();

-- ---------------------------------------------------------------------------
-- activities
-- ---------------------------------------------------------------------------
CREATE TABLE activities (
  id           uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  -- RB-02: toda actividad pertenece a un único evento.
  event_id     uuid         NOT NULL REFERENCES events (id),
  title        varchar(160) NOT NULL CHECK (length(trim(title)) > 0),
  description  text         NOT NULL DEFAULT '',
  due_at       timestamptz,
  status       varchar(20)  NOT NULL DEFAULT 'PENDING'
               CHECK (status IN ('PENDING', 'IN_PROGRESS', 'SUBMITTED', 'COMPLETED', 'CANCELLED')),
  created_by   uuid         NOT NULL REFERENCES users (id),
  created_at   timestamptz  NOT NULL DEFAULT now(),
  updated_at   timestamptz  NOT NULL DEFAULT now()
);
CREATE INDEX activities_event_status_idx ON activities (event_id, status);
CREATE INDEX activities_due_idx ON activities (due_at);
CREATE TRIGGER activities_updated_at BEFORE UPDATE ON activities
  FOR EACH ROW EXECUTE PROCEDURE set_updated_at();

-- ---------------------------------------------------------------------------
-- assignments
-- ---------------------------------------------------------------------------
CREATE TABLE assignments (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  activity_id  uuid        NOT NULL REFERENCES activities (id),
  user_id      uuid        NOT NULL REFERENCES users (id),
  -- RB-04: solo una asignación ACTIVE permite registrar evidencia.
  status       varchar(20) NOT NULL DEFAULT 'ACTIVE'
               CHECK (status IN ('ACTIVE', 'REVOKED')),
  assigned_by  uuid        NOT NULL REFERENCES users (id),
  assigned_at  timestamptz NOT NULL DEFAULT now(),
  revoked_at   timestamptz,
  -- RB-03: varios responsables por actividad, sin duplicar el mismo usuario.
  CONSTRAINT assignments_activity_user_uq UNIQUE (activity_id, user_id),
  CONSTRAINT assignments_revoked_chk CHECK ((status = 'REVOKED') = (revoked_at IS NOT NULL))
);
CREATE INDEX assignments_user_status_idx ON assignments (user_id, status);

-- ---------------------------------------------------------------------------
-- evidences
-- ---------------------------------------------------------------------------
CREATE TABLE evidences (
  id                uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  -- RB-05: vinculada a una asignación y al usuario que la creó.
  assignment_id     uuid          NOT NULL REFERENCES assignments (id),
  created_by        uuid          NOT NULL REFERENCES users (id),
  -- RB-10 / RF-14: clave de idempotencia generada por el cliente.
  client_uuid       uuid          NOT NULL UNIQUE,
  -- Ruta relativa en el almacenamiento de archivos (no en la base, §4.4.6).
  photo_path        varchar(500)  NOT NULL,
  photo_mime        varchar(50)   NOT NULL CHECK (photo_mime IN ('image/jpeg', 'image/png', 'image/webp')),
  photo_size_bytes  integer       NOT NULL CHECK (photo_size_bytes > 0),
  photo_sha256      char(64),
  -- RB-07: sin GPS, coordenadas NULL y location_status explica el motivo.
  latitude          numeric(9,6)  CHECK (latitude  BETWEEN -90  AND 90),
  longitude         numeric(9,6)  CHECK (longitude BETWEEN -180 AND 180),
  accuracy_m        numeric(8,2)  CHECK (accuracy_m > 0),
  location_status   varchar(30)   NOT NULL DEFAULT 'AVAILABLE'
                    CHECK (location_status IN ('AVAILABLE', 'PERMISSION_DENIED',
                      'PERMISSION_DENIED_FOREVER', 'SERVICE_DISABLED', 'UNAVAILABLE')),
  -- Hora del dispositivo y hora del servidor se conservan por separado (§4.3.5).
  captured_at       timestamptz   NOT NULL,
  received_at       timestamptz   NOT NULL DEFAULT now(),
  notes             text          NOT NULL DEFAULT '' CHECK (length(notes) <= 500),
  status            varchar(20)   NOT NULL DEFAULT 'PENDING_REVIEW'
                    CHECK (status IN ('PENDING_REVIEW', 'APPROVED', 'REJECTED')),
  CONSTRAINT evidences_coords_pair_chk CHECK ((latitude IS NULL) = (longitude IS NULL)),
  CONSTRAINT evidences_location_chk CHECK (
    (location_status = 'AVAILABLE') = (latitude IS NOT NULL)
  )
);
CREATE INDEX evidences_assignment_idx ON evidences (assignment_id);
CREATE INDEX evidences_status_received_idx ON evidences (status, received_at);
CREATE INDEX evidences_created_by_idx ON evidences (created_by);

-- ---------------------------------------------------------------------------
-- reviews  (RB-08, RB-09: historial de revisión)
-- ---------------------------------------------------------------------------
CREATE TABLE reviews (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  evidence_id  uuid        NOT NULL REFERENCES evidences (id),
  reviewer_id  uuid        NOT NULL REFERENCES users (id),
  result       varchar(20) NOT NULL CHECK (result IN ('APPROVED', 'REJECTED')),
  comment      text        NOT NULL DEFAULT '' CHECK (length(comment) <= 1000),
  reviewed_at  timestamptz NOT NULL DEFAULT now(),
  -- TC-20: el rechazo debe incluir motivo.
  CONSTRAINT reviews_reject_comment_chk CHECK (result = 'APPROVED' OR length(trim(comment)) > 0)
);
CREATE INDEX reviews_evidence_idx ON reviews (evidence_id, reviewed_at DESC);

-- ---------------------------------------------------------------------------
-- audit_logs  (RF-18). Nunca guardar contraseñas ni tokens.
-- ---------------------------------------------------------------------------
CREATE TABLE audit_logs (
  id          bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  actor_id    uuid         REFERENCES users (id),
  action      varchar(60)  NOT NULL,
  entity      varchar(60)  NOT NULL,
  entity_id   varchar(64),
  metadata    jsonb        NOT NULL DEFAULT '{}'::jsonb,
  ip          varchar(64),
  created_at  timestamptz  NOT NULL DEFAULT now()
);
CREATE INDEX audit_logs_entity_idx ON audit_logs (entity, entity_id);
CREATE INDEX audit_logs_actor_idx ON audit_logs (actor_id, created_at DESC);
CREATE INDEX audit_logs_created_idx ON audit_logs (created_at DESC);
