-- Catálogo inicial: los mismos ejercicios que trae la app (lib/data/seed.dart).
-- firmware_profile: 0 = sensor que rota con un miembro o una barra,
--                   1 = sensor que viaja con el torso (cintura o mochila).

INSERT INTO exercises
  (id, name, muscle_group, equipment, placement, placement_note, firmware_profile, tutorial_seconds)
VALUES
  -- Pecho
  ('bench-press', 'Press de banca', 'chest', 'barbell', 'equipment', 'Sobre la barra, en el centro.', 0, 48),
  ('incline-db-press', 'Press inclinado con mancuernas', 'chest', 'dumbbell', 'arm', 'En el antebrazo, cerca de la muñeca.', 0, 0),
  ('cable-fly', 'Aperturas en polea', 'chest', 'cable', 'arm', 'En el antebrazo, cerca de la muñeca.', 0, 0),
  ('push-up', 'Flexiones', 'chest', 'bodyweight', 'body', 'En la cintura o en una mochila pegada a la espalda.', 1, 35),
  ('machine-chest-press', 'Press en máquina', 'chest', 'machine', 'equipment', 'En el brazo de la máquina, cerca del agarre.', 0, 0),
  ('incline-bench-press', 'Press inclinado con barra', 'chest', 'barbell', 'equipment', 'Sobre la barra, en el centro.', 0, 0),
  ('dips', 'Fondos en paralelas', 'chest', 'bodyweight', 'body', 'En la cintura o en una mochila pegada a la espalda.', 1, 0),
  -- Espalda
  ('pull-up', 'Dominadas', 'back', 'bodyweight', 'body', 'En la cintura o en una mochila pegada a la espalda.', 1, 0),
  ('deadlift', 'Peso muerto', 'back', 'barbell', 'equipment', 'Sobre la barra, en el centro.', 0, 0),
  ('barbell-row', 'Remo con barra', 'back', 'barbell', 'equipment', 'Sobre la barra, en el centro.', 0, 0),
  ('db-row', 'Remo con mancuerna', 'back', 'dumbbell', 'arm', 'En el antebrazo, cerca de la muñeca.', 0, 0),
  ('lat-pulldown', 'Jalón al pecho', 'back', 'cable', 'arm', 'En el antebrazo, cerca de la muñeca.', 0, 0),
  ('seated-row', 'Remo sentado en polea', 'back', 'cable', 'arm', 'En el antebrazo, cerca de la muñeca.', 0, 0),
  -- Piernas
  ('squat', 'Sentadilla', 'legs', 'barbell', 'equipment', 'Sobre la barra, en el centro.', 0, 0),
  ('leg-press', 'Prensa de piernas', 'legs', 'machine', 'equipment', 'En el brazo de la máquina, cerca del agarre.', 0, 0),
  ('lunge', 'Zancadas con mancuernas', 'legs', 'dumbbell', 'body', 'En la cintura o en una mochila pegada a la espalda.', 1, 0),
  ('rdl', 'Peso muerto rumano', 'legs', 'barbell', 'equipment', 'Sobre la barra, en el centro.', 0, 0),
  ('leg-extension', 'Extensión de cuádriceps', 'legs', 'machine', 'equipment', 'En el brazo de la máquina, cerca del agarre.', 0, 0),
  ('leg-curl', 'Curl femoral', 'legs', 'machine', 'equipment', 'En el brazo de la máquina, cerca del agarre.', 0, 0),
  ('calf-raise', 'Elevación de talones', 'legs', 'machine', 'body', 'En la cintura o en una mochila pegada a la espalda.', 1, 0),
  -- Hombros
  ('db-shoulder-press', 'Press militar con mancuernas', 'shoulders', 'dumbbell', 'arm', 'En el antebrazo, cerca de la muñeca.', 0, 0),
  ('overhead-press', 'Press militar con barra', 'shoulders', 'barbell', 'equipment', 'Sobre la barra, en el centro.', 0, 0),
  ('lateral-raise', 'Elevaciones laterales', 'shoulders', 'dumbbell', 'arm', 'En el antebrazo, cerca de la muñeca.', 0, 0),
  ('face-pull', 'Face pull', 'shoulders', 'cable', 'arm', 'En el antebrazo, cerca de la muñeca.', 0, 0),
  -- Brazos
  ('biceps-curl', 'Curl de bíceps', 'arms', 'dumbbell', 'arm', 'En el antebrazo, cerca de la muñeca.', 0, 0),
  ('barbell-curl', 'Curl con barra', 'arms', 'barbell', 'equipment', 'Sobre la barra, en el centro.', 0, 0),
  ('hammer-curl', 'Curl martillo', 'arms', 'dumbbell', 'arm', 'En el antebrazo, cerca de la muñeca.', 0, 0),
  ('triceps-pushdown', 'Extensión de tríceps en polea', 'arms', 'cable', 'arm', 'En el antebrazo, cerca de la muñeca.', 0, 0),
  ('skull-crusher', 'Press francés', 'arms', 'barbell', 'equipment', 'Sobre la barra, en el centro.', 0, 0),
  -- Core
  ('crunch', 'Abdominales', 'core', 'bodyweight', 'body', 'En la cintura o en una mochila pegada a la espalda.', 1, 0),
  ('hanging-leg-raise', 'Elevación de piernas colgado', 'core', 'bodyweight', 'body', 'En la cintura o en una mochila pegada a la espalda.', 1, 0),
  ('cable-crunch', 'Crunch en polea', 'core', 'cable', 'body', 'En la cintura o en una mochila pegada a la espalda.', 1, 0);

INSERT INTO tutorial_steps (exercise_id, position, body) VALUES
  ('bench-press', 1, 'Empieza con los brazos extendidos. Esa es la posición de inicio que aprende el sensor.'),
  ('bench-press', 2, 'Baja la barra hasta el pecho, sin rebotar.'),
  ('bench-press', 3, 'Sube hasta extender los brazos. Cada subida completa cuenta una repetición.'),
  ('bench-press', 4, 'Mantén los pies firmes en el piso y la espalda apoyada en el banco.'),
  ('push-up', 1, 'Manos un poco más abiertas que los hombros, cuerpo recto.'),
  ('push-up', 2, 'Quédate arriba un segundo para que el sensor aprenda el inicio.'),
  ('push-up', 3, 'Baja hasta casi tocar el piso y vuelve a subir.');
