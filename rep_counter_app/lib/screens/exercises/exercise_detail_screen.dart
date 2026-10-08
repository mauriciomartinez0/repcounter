import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/models.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/sensor_diagram.dart';
import '../../workout/workout_controller.dart';
import '../workout/workout_flow_screen.dart';
import 'tutorial_screen.dart';

/// Exercise detail, option A of the mockups: tutorial behind a button.
/// "Empezar" opens a free workout with this exercise.
class ExerciseDetailScreen extends StatefulWidget {
  const ExerciseDetailScreen({super.key, required this.exercise});

  final Exercise exercise;

  @override
  State<ExerciseDetailScreen> createState() => _ExerciseDetailScreenState();
}

class _ExerciseDetailScreenState extends State<ExerciseDetailScreen> {
  late double? _weight =
      context.app.repository.lastWeight(widget.exercise.id) ??
          (widget.exercise.equipment == Equipment.bodyweight ? null : 20);

  @override
  Widget build(BuildContext context) {
    final repo = context.app.repository;
    final exercise = widget.exercise;
    final c = context.colors;
    final hasHistory = repo.lastWeight(exercise.id) != null;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BackHeader(actions: [
              ListenableBuilder(
                listenable: repo,
                builder: (context, _) {
                  final favorite = repo.favoriteIds.contains(exercise.id);
                  return IconTapTarget(
                    icon: favorite ? AppIconKind.star : AppIconKind.starOutline,
                    label: favorite
                        ? 'Quitar de favoritos'
                        : 'Agregar a favoritos',
                    onTap: () => repo.toggleFavorite(exercise.id),
                  );
                },
              ),
              const SizedBox(width: 8),
            ]),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: kGutter),
                children: [
                  const SizedBox(height: 8),
                  Text(exercise.name,
                      style: AppText.text(36,
                          weight: FontWeight.w500, height: 1.1, color: c.ink)),
                  const SizedBox(height: 6),
                  Text(
                    '${exercise.muscleGroup.label} · ${exercise.equipment.label}',
                    style: AppText.text(16, color: c.ink2),
                  ),
                  const SizedBox(height: 28),
                  const AppLabel('Dónde va el sensor'),
                  const SizedBox(height: 12),
                  SensorDiagram(exercise: exercise),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppIcon(exercise.placement.icon, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(
                              text: '${exercise.placement.label}. ',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            TextSpan(
                              text: exercise.placementNote,
                              style: TextStyle(color: c.ink2),
                            ),
                          ]),
                          style: AppText.text(17, color: c.ink),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  AppLabel(hasHistory ? 'Peso · última vez' : 'Peso'),
                  const SizedBox(height: 12),
                  WeightStepper(
                    valueKg: _weight,
                    onChanged: (kg) => setState(() => _weight = kg),
                  ),
                  if (exercise.hasTutorial) ...[
                    const SizedBox(height: 20),
                    Pressable(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => TutorialScreen(exercise: exercise),
                        ),
                      ),
                      child: Container(
                        height: 64,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: c.control),
                          borderRadius: BorderRadius.circular(kRadius),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: c.btnBg,
                              ),
                              child: Center(
                                child: AppIcon(AppIconKind.play,
                                    size: 18, color: c.btnInk),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Ver tutorial',
                                    style: AppText.text(17,
                                        weight: FontWeight.w600, color: c.ink)),
                                if (exercise.tutorialSeconds > 0)
                                  Text(
                                    'Video de ${exercise.tutorialSeconds} '
                                    'segundos',
                                    style: AppText.text(14, color: c.ink2),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 32),
              child: PrimaryButton(
                label: 'Empezar',
                onPressed: () => startWorkout(
                  context,
                  (app) => WorkoutController.free(
                    repository: app.repository,
                    sensor: app.sensor,
                    exercise: exercise,
                    weightKg: _weight,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
