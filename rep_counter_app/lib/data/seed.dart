// Starting data for the local repository. Once the backend exists the catalog
// comes from the API and this file only feeds tests and offline demos.

import 'dart:math';

import 'models.dart';

const _bar = 'Sobre la barra, en el centro.';
const _dumbbell = 'En el mango de la mancuerna.';
const _machine = 'En el brazo de la máquina, cerca del agarre.';
const _cable = 'En el agarre de la polea.';
const _wrist = 'En el antebrazo, cerca de la muñeca.';
const _waist = 'En la cintura o en una mochila pegada a la espalda.';

Exercise _ex(
  String id,
  String name,
  MuscleGroup group,
  Equipment equipment,
  SensorPlacement placement, {
  String? note,
  List<String> steps = const [],
  int seconds = 0,
}) =>
    Exercise(
      id: id,
      name: name,
      muscleGroup: group,
      equipment: equipment,
      placement: placement,
      placementNote: note ??
          switch (placement) {
            SensorPlacement.arm => _wrist,
            SensorPlacement.body => _waist,
            SensorPlacement.equipment => switch (equipment) {
                Equipment.barbell => _bar,
                Equipment.dumbbell => _dumbbell,
                Equipment.machine => _machine,
                Equipment.cable => _cable,
                Equipment.bodyweight => _waist,
              },
          },
      // The current firmware has two profiles: 0 for a sensor that rotates
      // with a limb or a bar, 1 for a sensor that travels with the torso.
      firmwareProfile: placement == SensorPlacement.body ? 1 : 0,
      tutorialSteps: steps,
      tutorialSeconds: seconds,
    );

final List<Exercise> seedExercises = [
  // Pecho
  _ex('bench-press', 'Press de banca', MuscleGroup.chest, Equipment.barbell,
      SensorPlacement.equipment,
      seconds: 48,
      steps: const [
        'Empieza con los brazos extendidos. Esa es la posición de inicio que '
            'aprende el sensor.',
        'Baja la barra hasta el pecho, sin rebotar.',
        'Sube hasta extender los brazos. Cada subida completa cuenta una '
            'repetición.',
        'Mantén los pies firmes en el piso y la espalda apoyada en el banco.',
      ]),
  _ex('incline-db-press', 'Press inclinado con mancuernas', MuscleGroup.chest,
      Equipment.dumbbell, SensorPlacement.arm),
  _ex('cable-fly', 'Aperturas en polea', MuscleGroup.chest, Equipment.cable,
      SensorPlacement.arm),
  _ex('push-up', 'Flexiones', MuscleGroup.chest, Equipment.bodyweight,
      SensorPlacement.body,
      seconds: 35,
      steps: const [
        'Manos un poco más abiertas que los hombros, cuerpo recto.',
        'Quédate arriba un segundo para que el sensor aprenda el inicio.',
        'Baja hasta casi tocar el piso y vuelve a subir.',
      ]),
  _ex('machine-chest-press', 'Press en máquina', MuscleGroup.chest,
      Equipment.machine, SensorPlacement.equipment),
  _ex('incline-bench-press', 'Press inclinado con barra', MuscleGroup.chest,
      Equipment.barbell, SensorPlacement.equipment),
  _ex('dips', 'Fondos en paralelas', MuscleGroup.chest, Equipment.bodyweight,
      SensorPlacement.body),

  // Espalda
  _ex('pull-up', 'Dominadas', MuscleGroup.back, Equipment.bodyweight,
      SensorPlacement.body),
  _ex('deadlift', 'Peso muerto', MuscleGroup.back, Equipment.barbell,
      SensorPlacement.equipment),
  _ex('barbell-row', 'Remo con barra', MuscleGroup.back, Equipment.barbell,
      SensorPlacement.equipment),
  _ex('db-row', 'Remo con mancuerna', MuscleGroup.back, Equipment.dumbbell,
      SensorPlacement.arm),
  _ex('lat-pulldown', 'Jalón al pecho', MuscleGroup.back, Equipment.cable,
      SensorPlacement.arm),
  _ex('seated-row', 'Remo sentado en polea', MuscleGroup.back,
      Equipment.cable, SensorPlacement.arm),

  // Piernas
  _ex('squat', 'Sentadilla', MuscleGroup.legs, Equipment.barbell,
      SensorPlacement.equipment),
  _ex('leg-press', 'Prensa de piernas', MuscleGroup.legs, Equipment.machine,
      SensorPlacement.equipment),
  _ex('lunge', 'Zancadas con mancuernas', MuscleGroup.legs,
      Equipment.dumbbell, SensorPlacement.body),
  _ex('rdl', 'Peso muerto rumano', MuscleGroup.legs, Equipment.barbell,
      SensorPlacement.equipment),
  _ex('leg-extension', 'Extensión de cuádriceps', MuscleGroup.legs,
      Equipment.machine, SensorPlacement.equipment),
  _ex('leg-curl', 'Curl femoral', MuscleGroup.legs, Equipment.machine,
      SensorPlacement.equipment),
  _ex('calf-raise', 'Elevación de talones', MuscleGroup.legs,
      Equipment.machine, SensorPlacement.body),

  // Hombros
  _ex('db-shoulder-press', 'Press militar con mancuernas',
      MuscleGroup.shoulders, Equipment.dumbbell, SensorPlacement.arm),
  _ex('overhead-press', 'Press militar con barra', MuscleGroup.shoulders,
      Equipment.barbell, SensorPlacement.equipment),
  _ex('lateral-raise', 'Elevaciones laterales', MuscleGroup.shoulders,
      Equipment.dumbbell, SensorPlacement.arm),
  _ex('face-pull', 'Face pull', MuscleGroup.shoulders, Equipment.cable,
      SensorPlacement.arm),

  // Brazos
  _ex('biceps-curl', 'Curl de bíceps', MuscleGroup.arms, Equipment.dumbbell,
      SensorPlacement.arm),
  _ex('barbell-curl', 'Curl con barra', MuscleGroup.arms, Equipment.barbell,
      SensorPlacement.equipment),
  _ex('hammer-curl', 'Curl martillo', MuscleGroup.arms, Equipment.dumbbell,
      SensorPlacement.arm),
  _ex('triceps-pushdown', 'Extensión de tríceps en polea', MuscleGroup.arms,
      Equipment.cable, SensorPlacement.arm),
  _ex('skull-crusher', 'Press francés', MuscleGroup.arms, Equipment.barbell,
      SensorPlacement.equipment),

  // Core
  _ex('crunch', 'Abdominales', MuscleGroup.core, Equipment.bodyweight,
      SensorPlacement.body),
  _ex('hanging-leg-raise', 'Elevación de piernas colgado', MuscleGroup.core,
      Equipment.bodyweight, SensorPlacement.body),
  _ex('cable-crunch', 'Crunch en polea', MuscleGroup.core, Equipment.cable,
      SensorPlacement.body),
];

final List<Routine> seedRoutines = [
  const Routine(id: 'r-push', name: 'Empuje', items: [
    RoutineItem(exerciseId: 'bench-press', sets: 4, reps: 8, weightKg: 60,
        restSeconds: 120),
    RoutineItem(exerciseId: 'db-shoulder-press', sets: 3, reps: 10,
        weightKg: 16, restSeconds: 90),
    RoutineItem(exerciseId: 'dips', sets: 3, reps: 12, restSeconds: 90),
    RoutineItem(exerciseId: 'lateral-raise', sets: 3, reps: 15, weightKg: 8,
        restSeconds: 60),
    RoutineItem(exerciseId: 'triceps-pushdown', sets: 3, reps: 12,
        weightKg: 25, restSeconds: 60),
  ]),
  const Routine(id: 'r-pull', name: 'Tirón', items: [
    RoutineItem(exerciseId: 'deadlift', sets: 3, reps: 5, weightKg: 90,
        restSeconds: 150),
    RoutineItem(exerciseId: 'pull-up', sets: 4, reps: 8, restSeconds: 90),
    RoutineItem(exerciseId: 'barbell-row', sets: 3, reps: 10, weightKg: 50,
        restSeconds: 90),
    RoutineItem(exerciseId: 'face-pull', sets: 3, reps: 15, weightKg: 20,
        restSeconds: 60),
    RoutineItem(exerciseId: 'biceps-curl', sets: 3, reps: 12, weightKg: 12,
        restSeconds: 60),
  ]),
  const Routine(id: 'r-legs', name: 'Pierna', items: [
    RoutineItem(exerciseId: 'squat', sets: 4, reps: 8, weightKg: 80,
        restSeconds: 150),
    RoutineItem(exerciseId: 'rdl', sets: 3, reps: 10, weightKg: 70,
        restSeconds: 120),
    RoutineItem(exerciseId: 'leg-press', sets: 3, reps: 12, weightKg: 140,
        restSeconds: 90),
    RoutineItem(exerciseId: 'lunge', sets: 3, reps: 12, weightKg: 14,
        restSeconds: 90),
    RoutineItem(exerciseId: 'leg-curl', sets: 3, reps: 12, weightKg: 35,
        restSeconds: 60),
    RoutineItem(exerciseId: 'calf-raise', sets: 4, reps: 15, weightKg: 60,
        restSeconds: 60),
  ]),
];

/// Twelve weeks of plausible history so Historial and Progreso have
/// something to draw before the first real workout.
List<WorkoutSession> seedSessions(DateTime now) {
  final random = Random(7);
  final sessions = <WorkoutSession>[];
  final today = DateTime(now.year, now.month, now.day);
  const weeks = 12;

  for (var week = weeks; week >= 1; week--) {
    final progress = (weeks - week) / (weeks - 1); // 0 → 1 over the period
    final weekStart = today.subtract(Duration(days: week * 7));
    for (final (dayOffset, routine) in [
      (0, seedRoutines[0]),
      (2, seedRoutines[2]),
      (4, seedRoutines[1]),
    ]) {
      final start = weekStart
          .add(Duration(days: dayOffset, hours: 18, minutes: random.nextInt(40)));
      var clock = start;
      final sets = <SetRecord>[];
      for (final item in routine.items) {
        // Weights climb toward the routine's current plan in 2.5 kg steps.
        double? weight;
        if (item.weightKg != null) {
          final planned = item.weightKg!;
          final raw = planned * (0.875 + 0.125 * progress);
          weight = (raw / 2.5).floor() * 2.5;
          if (weight <= 0) weight = planned;
        }
        for (var s = 1; s <= item.sets; s++) {
          clock = clock.add(Duration(seconds: 40 + item.restSeconds));
          // Fatigue: later sets tend to fall short of the target, less so
          // as the weeks go by.
          final missed =
              (random.nextDouble() * (s - 1) * (1.4 - progress)).floor();
          sets.add(SetRecord(
            exerciseId: item.exerciseId,
            setNumber: s,
            reps: item.reps - missed,
            targetReps: item.reps,
            weightKg: weight,
            meanVelocity: double.parse(
              (0.38 + 0.08 * progress + random.nextDouble() * 0.06 - 0.01 * s)
                  .toStringAsFixed(2),
            ),
            rangeDegrees: 78 + random.nextDouble() * 10,
            completedAt: clock,
          ));
        }
      }
      sessions.add(WorkoutSession(
        id: 's-${start.millisecondsSinceEpoch}',
        routineId: routine.id,
        title: routine.name,
        startedAt: start,
        endedAt: clock.add(const Duration(minutes: 2)),
        plannedExercises: routine.items.length,
        sets: sets,
      ));
    }
  }
  sessions.removeWhere((s) => s.startedAt.isAfter(now));
  sessions.sort((a, b) => b.startedAt.compareTo(a.startedAt));
  return sessions;
}
