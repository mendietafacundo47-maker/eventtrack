-- Rollback de 001_initial_schema. Elimina TODOS los datos de EventTrack.
-- Ejecutar solo en desarrollo o tras respaldar la base (§4.5.6).

DROP TABLE IF EXISTS audit_logs;
DROP TABLE IF EXISTS reviews;
DROP TABLE IF EXISTS evidences;
DROP TABLE IF EXISTS assignments;
DROP TABLE IF EXISTS activities;
DROP TABLE IF EXISTS events;
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS roles;
DROP FUNCTION IF EXISTS set_updated_at();
