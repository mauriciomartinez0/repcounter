-- Ejercicios con barra que sube y baja sin girar: el perfil de inclinación no
-- los puede contar (en la barra del press banca el ángulo casi no cambia).
-- Cuentan como la pila, por la altura de la barra, y el sensor puede ir en
-- cualquier orientación.
--
-- Perfil 3: la barra empieza arriba y baja primero (press banca, sentadilla,
-- peso muerto rumano). El firmware cuenta la curva al revés, así que la
-- repetición suma al terminar de subir.
UPDATE exercises
   SET firmware_profile = 3
 WHERE id IN (
  'bench-press',
  'close-grip-bench-press',
  'decline-bench-press',
  'good-morning',
  'incline-bench-press',
  'jm-press',
  'rdl',
  'smith-bench-press',
  'smith-incline-press',
  'smith-squat',
  'squat',
  'front-squat',
  'overhead-squat',
  'zercher-squat',
  'barbell-split-squat',
  'barbell-lunge',
  'barbell-reverse-lunge',
  'stiff-leg-deadlift',
  'wide-bench-press'
);

-- Perfil 2: la barra empieza abajo y sube primero (peso muerto, press
-- militar, remos), igual que una pila.
UPDATE exercises
   SET firmware_profile = 2
 WHERE id IN (
  'barbell-calf-raise',
  'barbell-row',
  'barbell-shrug',
  'barbell-step-up',
  'barbell-upright-row',
  'deadlift',
  'hip-thrust',
  'overhead-press',
  'pendlay-row',
  'power-clean',
  'rack-pull',
  'reverse-grip-row',
  'seated-overhead-press',
  'smith-row',
  'smith-shoulder-press',
  'sumo-deadlift',
  'trap-bar-deadlift'
);

-- Los curls, elevaciones frontales, pullover, press francés y extensiones
-- giran la barra con los antebrazos: siguen con inclinación (perfil 0). El
-- thruster mezcla bajada y subida en una sola repetición y también se queda.
