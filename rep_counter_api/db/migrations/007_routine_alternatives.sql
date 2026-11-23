-- Alternativas de un ejercicio dentro de una rutina: otros ejercicios que
-- sirven en su lugar ("elevaciones laterales en polea" si la máquina está
-- ocupada). En orden; vacío si no tiene. Las series, repeticiones, peso y
-- descanso del ítem valen para cualquiera de ellas.
ALTER TABLE routine_items
  ADD COLUMN alternative_ids text[] NOT NULL DEFAULT '{}';
