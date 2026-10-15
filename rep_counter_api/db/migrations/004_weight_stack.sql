-- Ejercicios que levantan una pila de pesas: todos los de polea y las máquinas
-- de selector (la carga se elige con un pasador, sin cambiar discos). El
-- sensor va encima de la pila, pegado a la placa superior, y cuenta con el
-- perfil 2 del firmware, que sigue el movimiento vertical en lugar de la
-- inclinación (la pila sube y baja sin girar).
--
-- Las máquinas de discos (prensa, hack, remo en T, remo alto, Smith, talones)
-- no tienen pila y se quedan como estaban.

UPDATE exercises
   SET placement = 'equipment',
       placement_note = 'Encima de la pila de pesas, pegado a la placa superior.',
       firmware_profile = 2
 WHERE id IN (
  'cable-chest-press',
  'cable-crossover',
  'cable-crunch',
  'cable-curl',
  'cable-external-rotation',
  'cable-fly',
  'cable-front-raise',
  'cable-glute-kickback',
  'cable-hammer-curl',
  'cable-kickback',
  'cable-lateral-raise',
  'cable-overhead-extension',
  'cable-pull-through',
  'cable-reverse-fly',
  'cable-upright-row',
  'face-pull',
  'hip-abduction',
  'hip-adduction',
  'incline-cable-fly',
  'lat-pulldown',
  'leg-curl',
  'leg-extension',
  'low-cable-fly',
  'machine-chest-press',
  'machine-crunch',
  'machine-dip',
  'machine-lateral-raise',
  'machine-preacher-curl',
  'machine-pulldown',
  'machine-reverse-fly',
  'machine-row',
  'machine-shoulder-press',
  'machine-triceps-extension',
  'neutral-pulldown',
  'one-arm-cable-row',
  'one-arm-pushdown',
  'pec-deck',
  'reverse-grip-pulldown',
  'reverse-pushdown',
  'rope-pushdown',
  'rope-seated-row',
  'seated-leg-curl',
  'seated-row',
  'straight-arm-pulldown',
  'triceps-pushdown',
  'wide-seated-row'
);
