-- Historial editable y curva del movimiento de cada serie.
--
-- Las sesiones ya subidas se pueden corregir (repeticiones, peso, series de
-- más) y borrar desde el historial. Igual que las rutinas:
--   - edited_at: cuándo se editó en el teléfono. Si dos teléfonos la editan
--     sin conexión, gana la edición posterior.
--   - deleted_at: "lápida". La sesión queda para que la sincronización avise
--     del borrado a los demás teléfonos; sus series se borran.
--   - updated_at: cualquier cambio en el servidor. La sincronización de
--     sesiones pasa a leer esta columna en lugar de received_at.

ALTER TABLE workout_sessions
  ADD COLUMN edited_at  timestamptz,
  ADD COLUMN deleted_at timestamptz,
  ADD COLUMN updated_at timestamptz;

-- Hasta ahora una sesión solo cambiaba al llegar, así que el cursor que ya
-- tienen los teléfonos (sobre received_at) sigue sirviendo.
UPDATE workout_sessions SET updated_at = received_at;

ALTER TABLE workout_sessions
  ALTER COLUMN updated_at SET NOT NULL,
  ALTER COLUMN updated_at SET DEFAULT now();

CREATE TRIGGER workout_sessions_touch BEFORE UPDATE ON workout_sessions
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE INDEX workout_sessions_sync ON workout_sessions (user_id, updated_at);

-- Curva de la serie, grabada por el teléfono con los paquetes de la placa:
--   {"kind": "height", "sampleHz": 10, "values": [...]}  altura de la pila en cm
--   {"kind": "angle",  "sampleHz": 10, "values": [...]}  ángulo en grados
-- Null en las series grabadas antes de esto o sin sensor.
ALTER TABLE set_records ADD COLUMN trace jsonb;
