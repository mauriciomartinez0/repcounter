import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/models.dart';
import '../../theme/app_theme.dart';
import '../../util/format.dart';
import '../../widgets/common.dart';
import '../../workout/workout_controller.dart';
import '../exercises/exercise_browser.dart';
import '../exercises/exercise_detail_screen.dart';
import '../workout/workout_flow_screen.dart';
import 'routine_editor_screen.dart';

String routineSubtitle(Routine routine) {
  final n = routine.items.length;
  return '$n ${plural(n, 'ejercicio', 'ejercicios')} · '
      '${routine.estimatedMinutes} min';
}

/// "4 × 8 · 60 kg · descanso 2:00".
String routineItemLine(RoutineItem item) =>
    '${item.sets} × ${item.reps} · '
    '${item.weightKg == null ? 'peso corporal' : '${formatKg(item.weightKg!)} kg'}'
    ' · descanso ${formatClock(item.restSeconds)}';

class RoutineDetailScreen extends StatelessWidget {
  const RoutineDetailScreen({super.key, required this.routineId});

  final String routineId;

  @override
  Widget build(BuildContext context) {
    final repo = context.app.repository;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final c = context.colors;
        final routine = repo.routine(routineId);
        if (routine == null) {
          // Deleted from the editor.
          return const Scaffold(body: SizedBox.shrink());
        }
        final items = routine.items;
        return Scaffold(
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const BackHeader(),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: kGutter),
                    children: [
                      const SizedBox(height: 8),
                      Text(routine.name,
                          style: AppText.text(36,
                              weight: FontWeight.w500,
                              height: 1.1,
                              color: c.ink)),
                      const SizedBox(height: 6),
                      Text(routineSubtitle(routine),
                          style: AppText.text(16, color: c.ink2)),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          SmallButton(
                            label: 'Editar',
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    RoutineEditorScreen(routine: routine),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SmallButton(
                            label: 'Duplicar',
                            onPressed: () async {
                              final copy =
                                  await repo.duplicateRoutine(routine.id);
                              if (!context.mounted) return;
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      RoutineDetailScreen(routineId: copy.id),
                                ),
                              );
                              showMessage(context, 'Rutina duplicada.');
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (items.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 24),
                          child: Text(
                            'Esta rutina no tiene ejercicios. Agrégalos desde '
                            'Editar.',
                            style: AppText.text(16, color: c.ink2),
                          ),
                        ),
                      for (final (i, item) in items.indexed)
                        _ItemRow(
                          index: i + 1,
                          item: item,
                          exercise: repo.exercise(item.exerciseId),
                          last: i == items.length - 1,
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(kGutter, 16, kGutter, 32),
                  child: PrimaryButton(
                    label: 'Empezar entrenamiento',
                    onPressed: items.isEmpty
                        ? null
                        : () => startWorkout(
                              context,
                              (app) => WorkoutController.routine(
                                repository: app.repository,
                                sensor: app.sensor,
                                routine: routine,
                              ),
                            ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.index,
    required this.item,
    required this.exercise,
    required this.last,
  });

  final int index;
  final RoutineItem item;
  final Exercise? exercise;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final exercise = this.exercise;
    return Pressable(
      onTap: exercise == null
          ? null
          : () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ExerciseDetailScreen(exercise: exercise),
                ),
              ),
      child: Container(
        height: 84,
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: c.line),
            bottom: last ? BorderSide(color: c.line) : BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Text('$index', style: AppText.number(22, color: c.ink3)),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(exercise?.name ?? 'Ejercicio no disponible',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.text(19,
                          weight: FontWeight.w500, color: c.ink)),
                  const SizedBox(height: 4),
                  Text(routineItemLine(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.text(15, color: c.ink2)),
                ],
              ),
            ),
            if (exercise != null) PlacementTag(placement: exercise.placement),
          ],
        ),
      ),
    );
  }
}
