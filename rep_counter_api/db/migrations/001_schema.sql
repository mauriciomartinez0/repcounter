-- Rep Counter: esquema inicial.
--
-- Decisiones que conviene conocer antes de tocarlo:
--
-- * Las rutinas y las sesiones usan UUID generados por el TELÉFONO, no por la
--   base. Así una sesión hecha sin internet ya tiene su id definitivo y, si la
--   subida se reintenta, el servidor reconoce el id y no la duplica.
-- * Las rutinas no se borran: se marcan con deleted_at (una "lápida"), para
--   que los otros teléfonos del usuario se enteren del borrado al sincronizar.
-- * updated_at es la hora del SERVIDOR (cursor de sincronización); edited_at
--   es la hora en que el usuario editó en el teléfono (decide qué versión gana
--   cuando dos teléfonos editan la misma rutina sin conexión).
-- * Las sesiones y sus series son inmutables una vez subidas.
-- * Los ejercicios usan un id de texto legible ('bench-press') porque la app
--   también los trae incluidos y los referencia sin consultar al servidor.

CREATE EXTENSION IF NOT EXISTS citext;

CREATE TYPE muscle_group AS ENUM ('chest', 'back', 'legs', 'shoulders', 'arms', 'core');
CREATE TYPE equipment AS ENUM ('barbell', 'dumbbell', 'machine', 'bodyweight', 'cable');
CREATE TYPE sensor_placement AS ENUM ('arm', 'body', 'equipment');

CREATE FUNCTION touch_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$;

-- ---------------------------------------------------------------------------
-- Cuentas
-- ---------------------------------------------------------------------------

CREATE TABLE users (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name          text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 100),
  email         citext NOT NULL UNIQUE CHECK (email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  -- Null en cuentas creadas solo con Google.
  password_hash text,
  -- Identificador estable de la cuenta de Google ("sub" del ID token).
  google_sub    text UNIQUE,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT users_has_login CHECK (password_hash IS NOT NULL OR google_sub IS NOT NULL)
);

CREATE TRIGGER users_touch BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- Tokens de larga duración para renovar el acceso sin volver a pedir la
-- contraseña. Se guarda solo el hash. Cada uso emite uno nuevo y revoca el
-- anterior (rotación); si llega uno ya revocado, alguien lo copió y se
-- revocan todos los del usuario.
CREATE TABLE refresh_tokens (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES users ON DELETE CASCADE,
  token_hash  bytea NOT NULL UNIQUE,
  created_at  timestamptz NOT NULL DEFAULT now(),
  expires_at  timestamptz NOT NULL,
  revoked_at  timestamptz,
  replaced_by uuid REFERENCES refresh_tokens ON DELETE SET NULL
);

CREATE INDEX refresh_tokens_user ON refresh_tokens (user_id) WHERE revoked_at IS NULL;

CREATE TABLE password_reset_tokens (
  token_hash bytea PRIMARY KEY,
  user_id    uuid NOT NULL REFERENCES users ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  used_at    timestamptz
);

CREATE INDEX password_reset_tokens_user ON password_reset_tokens (user_id);

-- ---------------------------------------------------------------------------
-- Catálogo de ejercicios (lo administra el equipo, no los usuarios)
-- ---------------------------------------------------------------------------

CREATE TABLE exercises (
  id                text PRIMARY KEY CHECK (id ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  name              text NOT NULL UNIQUE,
  muscle_group      muscle_group NOT NULL,
  equipment         equipment NOT NULL,
  placement         sensor_placement NOT NULL,
  -- "Sobre la barra, en el centro."
  placement_note    text NOT NULL,
  -- Id de ejercicio que entiende la placa (CMD_SET_EXERCISE).
  firmware_profile  smallint NOT NULL DEFAULT 0 CHECK (firmware_profile BETWEEN 0 AND 255),
  -- Ángulo que hay que pasar para que una repetición cuente.
  threshold_degrees smallint NOT NULL DEFAULT 70 CHECK (threshold_degrees BETWEEN 1 AND 90),
  video_url         text,
  tutorial_seconds  integer NOT NULL DEFAULT 0 CHECK (tutorial_seconds >= 0),
  -- Retirar un ejercicio sin romper el historial que lo usa.
  active            boolean NOT NULL DEFAULT true,
  updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER exercises_touch BEFORE UPDATE ON exercises
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TABLE tutorial_steps (
  exercise_id text NOT NULL REFERENCES exercises ON DELETE CASCADE,
  position    smallint NOT NULL CHECK (position >= 1),
  body        text NOT NULL CHECK (length(btrim(body)) > 0),
  PRIMARY KEY (exercise_id, position)
);

-- Cambiar un paso del tutorial cuenta como cambio del ejercicio, para que la
-- versión del catálogo (ETag) cambie y los teléfonos lo vuelvan a descargar.
CREATE FUNCTION touch_exercise_from_step() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  UPDATE exercises SET updated_at = now()
   WHERE id = COALESCE(NEW.exercise_id, OLD.exercise_id);
  RETURN NULL;
END $$;

CREATE TRIGGER tutorial_steps_touch AFTER INSERT OR UPDATE OR DELETE ON tutorial_steps
  FOR EACH ROW EXECUTE FUNCTION touch_exercise_from_step();

-- Versión del catálogo. Cambia con cualquier alta, baja o edición.
CREATE VIEW catalog_version AS
SELECT md5(count(*)::text || ':' || COALESCE(max(updated_at)::text, '')) AS etag
  FROM exercises;

-- ---------------------------------------------------------------------------
-- Datos de cada usuario
-- ---------------------------------------------------------------------------

CREATE TABLE favorites (
  user_id     uuid NOT NULL REFERENCES users ON DELETE CASCADE,
  exercise_id text NOT NULL REFERENCES exercises,
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, exercise_id)
);

CREATE TABLE routines (
  id         uuid PRIMARY KEY,
  user_id    uuid NOT NULL REFERENCES users ON DELETE CASCADE,
  name       text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 100),
  created_at timestamptz NOT NULL DEFAULT now(),
  -- Hora de la edición en el teléfono; gana la más reciente.
  edited_at  timestamptz NOT NULL,
  -- Hora del servidor; cursor para "dame lo que cambió desde X".
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  -- Permite que las sesiones referencien (usuario, rutina) y así la base
  -- garantiza que nadie enlace una sesión a la rutina de otro.
  UNIQUE (user_id, id)
);

CREATE TRIGGER routines_touch BEFORE UPDATE ON routines
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE INDEX routines_sync ON routines (user_id, updated_at);

CREATE TABLE routine_items (
  routine_id   uuid NOT NULL REFERENCES routines ON DELETE CASCADE,
  position     smallint NOT NULL CHECK (position >= 1),
  exercise_id  text NOT NULL REFERENCES exercises,
  sets         smallint NOT NULL CHECK (sets BETWEEN 1 AND 20),
  reps         smallint NOT NULL CHECK (reps BETWEEN 1 AND 100),
  -- Null = peso corporal.
  weight_kg    numeric(5, 2) CHECK (weight_kg > 0 AND weight_kg <= 500),
  rest_seconds smallint NOT NULL CHECK (rest_seconds BETWEEN 0 AND 900),
  PRIMARY KEY (routine_id, position)
);

CREATE TABLE workout_sessions (
  id                uuid PRIMARY KEY,
  user_id           uuid NOT NULL REFERENCES users ON DELETE CASCADE,
  -- Null en entrenamiento libre.
  routine_id        uuid,
  -- Nombre de la rutina en ese momento, o "Entrenamiento libre". Se copia
  -- para que renombrar la rutina no reescriba el historial.
  title             text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 100),
  started_at        timestamptz NOT NULL,
  ended_at          timestamptz NOT NULL,
  planned_exercises smallint NOT NULL DEFAULT 0 CHECK (planned_exercises >= 0),
  -- Cuándo llegó al servidor (puede ser días después si no había internet).
  received_at       timestamptz NOT NULL DEFAULT now(),
  CHECK (ended_at >= started_at),
  FOREIGN KEY (user_id, routine_id) REFERENCES routines (user_id, id)
    ON DELETE SET NULL (routine_id)
);

CREATE INDEX workout_sessions_history ON workout_sessions (user_id, started_at DESC, id DESC);
CREATE INDEX workout_sessions_routine ON workout_sessions (routine_id) WHERE routine_id IS NOT NULL;

CREATE TABLE set_records (
  session_id    uuid NOT NULL REFERENCES workout_sessions ON DELETE CASCADE,
  -- Orden dentro de la sesión.
  position      smallint NOT NULL CHECK (position >= 1),
  exercise_id   text NOT NULL REFERENCES exercises,
  set_number    smallint NOT NULL CHECK (set_number >= 1),
  reps          smallint NOT NULL CHECK (reps BETWEEN 0 AND 1000),
  target_reps   smallint CHECK (target_reps BETWEEN 1 AND 1000),
  weight_kg     numeric(5, 2) CHECK (weight_kg > 0 AND weight_kg <= 500),
  -- m/s; null si la placa no la reportó.
  mean_velocity numeric(4, 2) CHECK (mean_velocity >= 0 AND mean_velocity <= 10),
  -- Ángulo máximo alcanzado en la serie.
  range_degrees numeric(4, 1) CHECK (range_degrees >= 0 AND range_degrees <= 180),
  completed_at  timestamptz NOT NULL,
  PRIMARY KEY (session_id, position)
);

CREATE INDEX set_records_exercise ON set_records (exercise_id, session_id);

-- Totales por sesión para el historial.
CREATE VIEW session_totals AS
SELECT session_id,
       count(*)                                   AS set_count,
       count(DISTINCT exercise_id)                AS exercise_count,
       COALESCE(sum(reps * weight_kg), 0)::numeric(10, 2) AS volume_kg
  FROM set_records
 GROUP BY session_id;
