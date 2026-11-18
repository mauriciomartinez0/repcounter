-- Ejercicios agregados después de la 003 y la 004, del mismo dataset
-- (https://github.com/hasaneyldrm/exercises-dataset, MIT). Los de pila de
-- pesas entran ya con la colocación y el perfil 2 de la 004.

INSERT INTO exercises
  (id, name, muscle_group, equipment, placement, placement_note, firmware_profile, tutorial_seconds)
VALUES
  ('one-arm-cable-lateral-raise', 'Elevaciones laterales a una mano en polea', 'shoulders', 'cable', 'equipment', 'Encima de la pila de pesas, pegado a la placa superior.', 2, 0);

INSERT INTO tutorial_steps (exercise_id, position, body)
VALUES
  ('one-arm-cable-lateral-raise', 1, 'Ponte de pie con los pies separados a la altura de los hombros, frente a la máquina de cable.'),
  ('one-arm-cable-lateral-raise', 2, 'Sujeta la agarradera del cable con una mano, con la palma hacia abajo, y colócate lo suficientemente alejado de la máquina para que haya tensión en el cable.'),
  ('one-arm-cable-lateral-raise', 3, 'Mantén el brazo recto y levántalo lentamente hacia el lado hasta que quede paralelo al suelo.'),
  ('one-arm-cable-lateral-raise', 4, 'Haz una pausa breve en la parte más alta, luego baja lentamente el brazo de vuelta a la posición inicial.'),
  ('one-arm-cable-lateral-raise', 5, 'Repite el número de repeticiones deseado, luego cambia de lado.');
