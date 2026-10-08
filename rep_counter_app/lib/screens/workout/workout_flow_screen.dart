import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/models.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../util/format.dart';
import '../../widgets/common.dart';
import '../../workout/workout_controller.dart';
import '../connection_screen.dart';
import '../exercises/exercise_picker_screen.dart';
import 'summary_screen.dart';

/// Makes sure the sensor is connected, then opens the workout.
Future<void> startWorkout(
  BuildContext context,
  WorkoutController Function(AppServices app) create,
) async {
  final app = context.app;
  if (!app.sensor.connected) {
    final connected = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const ConnectionScreen(popOnConnect: true),
      ),
    );
    if (connected != true || !context.mounted) return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => WorkoutFlowScreen(controller: create(app)),
    ),
  );
}

/// Calibración → Contador → Descanso → … → Resumen, driven by the
/// controller's phase.
class WorkoutFlowScreen extends StatefulWidget {
  const WorkoutFlowScreen({super.key, required this.controller});

  final WorkoutController controller;

  @override
  State<WorkoutFlowScreen> createState() => _WorkoutFlowScreenState();
}

class _WorkoutFlowScreenState extends State<WorkoutFlowScreen> {
  WorkoutController get _workout => widget.controller;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _workout.addListener(_onChange);
    _workout.start();
  }

  @override
  void dispose() {
    _workout.removeListener(_onChange);
    _workout.dispose();
    super.dispose();
  }

  void _onChange() {
    if (_workout.phase == WorkoutPhase.finished && !_closing) _close();
  }

  Future<void> _close() async {
    _closing = true;
    final session = await _workout.finish();
    if (!mounted) return;
    if (session == null) {
      Navigator.of(context).pop();
      return;
    }
    tick();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => SummaryScreen(session: session, justFinished: true),
      ),
    );
  }

  Future<void> _askToEnd() async {
    final hasSets = _workout.records.isNotEmpty || _workout.reps > 0;
    final end = await confirm(
      context,
      title: '¿Terminar entrenamiento?',
      message: hasSets
          ? 'Se guardan las series que ya hiciste.'
          : 'Todavía no hay series; no se guardará nada.',
      confirmLabel: 'Terminar',
      cancelLabel: 'Seguir',
    );
    if (end && mounted && !_closing) _close();
  }

  Future<void> _pickExercise() async {
    final picked = await Navigator.of(context).push<List<Exercise>>(
      MaterialPageRoute(
        builder: (_) => const ExercisePickerScreen(
          title: 'Cambiar ejercicio',
          single: true,
        ),
      ),
    );
    if (picked != null && picked.isNotEmpty) {
      _workout.changeExercise(picked.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _askToEnd();
      },
      child: ListenableBuilder(
        listenable: _workout,
        builder: (context, _) {
          final c = context.colors;
          final hit = _workout.phase == WorkoutPhase.counting &&
              _workout.targetReached;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            color: hit ? c.hitBg : c.bg,
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: SafeArea(
                child: switch (_workout.phase) {
                  WorkoutPhase.calibrating =>
                    _CalibrationView(workout: _workout),
                  WorkoutPhase.counting => _CounterView(workout: _workout),
                  WorkoutPhase.resting => _RestView(
                      workout: _workout,
                      onChangeExercise: _pickExercise,
                      onEnd: _askToEnd,
                    ),
                  WorkoutPhase.finished => const SizedBox.shrink(),
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CalibrationView extends StatelessWidget {
  const _CalibrationView({required this.workout});

  final WorkoutController workout;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sensor = context.app.sensor;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 48,
            child: Row(
              children: [
                Expanded(
                  child: Text(workout.exercise.name,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.text(16, color: c.ink2)),
                ),
                const SensorBadge(),
              ],
            ),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Quédate quieto en posición de inicio',
                  textAlign: TextAlign.center,
                  style: AppText.text(44, height: 1.12, color: c.ink),
                ),
                const SizedBox(height: 48),
                if (sensor.connected) ...[
                  // The board does not report progress; this fills over the
                  // usual time and waits near the end for its confirmation.
                  TweenAnimationBuilder<double>(
                    key: ValueKey(workout.exercise.id),
                    tween: Tween(begin: 0, end: 0.9),
                    duration: const Duration(milliseconds: 1500),
                    builder: (context, value, _) =>
                        ProgressTrack(value: value, fill: c.mark),
                  ),
                  const SizedBox(height: 12),
                  const AppLabel('Calibrando sensor',
                      textAlign: TextAlign.center),
                ] else ...[
                  Text(
                    'El sensor está desconectado.',
                    textAlign: TextAlign.center,
                    style: AppText.text(18, color: c.ink2),
                  ),
                  const SizedBox(height: 20),
                  SecondaryButton(
                    label: 'Conectar sensor',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            const ConnectionScreen(popOnConnect: true),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CounterView extends StatefulWidget {
  const _CounterView({required this.workout});

  final WorkoutController workout;

  @override
  State<_CounterView> createState() => _CounterViewState();
}

class _CounterViewState extends State<_CounterView> {
  double _lastAngle = 0;
  bool _rising = true;
  int _lastReps = 0;

  @override
  Widget build(BuildContext context) {
    final workout = widget.workout;
    final c = context.colors;
    final state = workout.sensor.state;
    final angle = state.angleDegrees.clamp(0.0, 90.0);
    final threshold = workout.exercise.thresholdDegrees.toDouble();
    final hit = workout.targetReached;

    // Direction from the angle trend, with a little hysteresis so noise at
    // the top or bottom does not flicker the arrow.
    if (angle > _lastAngle + 0.8) {
      _rising = true;
      _lastAngle = angle;
    } else if (angle < _lastAngle - 0.8) {
      _rising = false;
      _lastAngle = angle;
    }
    if (workout.reps > _lastReps) tick();
    _lastReps = workout.reps;

    return Padding(
      padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 48,
            child: Row(
              children: [
                Pressable(
                  onTap: workout.restartSet,
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: c.control),
                      borderRadius: BorderRadius.circular(kRadius),
                    ),
                    child: Text('REINICIAR',
                        style: AppText.text(13,
                                weight: FontWeight.w600, color: c.ink2)
                            .copyWith(letterSpacing: 13 * 0.08)),
                  ),
                ),
                const Spacer(),
                const SensorBadge(),
              ],
            ),
          ),
          if (!workout.isFree) ...[
            const SizedBox(height: 20),
            Text(workout.exercise.name,
                style: AppText.text(20, weight: FontWeight.w500, color: c.ink)),
            const SizedBox(height: 4),
            Text(
              'Serie ${workout.setNumber} de ${workout.totalSets} · '
              'objetivo ${workout.targetReps}',
              style: AppText.text(20, color: c.ink2),
            ),
          ],
          Expanded(
            child: Pressable(
              onTap: workout.finishSet,
              semanticLabel:
                  '${workout.reps} repeticiones. Toca para terminar la serie.',
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${workout.reps}',
                        style: AppText.number(360,
                                height: 0.8, color: hit ? c.hitInk : c.ink)
                            .copyWith(letterSpacing: -7.2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  // Not in the mockups: free training needs a way to close a
                  // set, and in a routine it closes early.
                  AppLabel(
                    hit
                        ? 'Toca para terminar o sigue sumando'
                        : 'Toca el número para terminar la serie',
                    color: c.ink3,
                  ),
                ],
              ),
            ),
          ),
          Row(
            children: [
              AppIcon(
                _rising ? AppIconKind.arrowUp : AppIconKind.arrowDown,
                size: 18,
                strokeWidth: 2,
                color: c.ink2,
              ),
              const SizedBox(width: 8),
              Text(_rising ? 'SUBIENDO' : 'BAJANDO',
                  style: AppText.text(14, weight: FontWeight.w600, color: c.ink2)
                      .copyWith(letterSpacing: 14 * 0.08)),
              const Spacer(),
              Text('${angle.round()}°',
                  style: AppText.number(28, color: c.ink)),
            ],
          ),
          const SizedBox(height: 12),
          // The live angle is the signal the counter runs on. Seeing it
          // makes a missed rep diagnosable instead of mysterious: if the bar
          // never reaches the threshold mark, the range of motion is short.
          SizedBox(
            height: 20,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                return Stack(
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 8,
                      height: 4,
                      child: ColoredBox(color: c.track),
                    ),
                    Positioned(
                      left: 0,
                      top: 8,
                      height: 4,
                      width: w * angle / 90,
                      child: ColoredBox(
                        color: angle >= threshold ? c.mark : c.ink,
                      ),
                    ),
                    Positioned(
                      left: w * threshold / 90 - 1,
                      top: 0,
                      width: 2,
                      height: 20,
                      child: ColoredBox(color: c.mark),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          DefaultTextStyle(
            style: AppText.text(13, color: c.ink3),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('0°'),
                Text('Umbral ${threshold.round()}°'),
                const Text('90°'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RestView extends StatelessWidget {
  const _RestView({
    required this.workout,
    required this.onChangeExercise,
    required this.onEnd,
  });

  final WorkoutController workout;
  final VoidCallback onChangeExercise;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final last = workout.lastRecord;
    final next = workout.next;
    final total = workout.restTotal;
    final velocity = workout.lastSetVelocity;

    final repsValue = Text.rich(
      TextSpan(children: [
        TextSpan(
          text: '${last?.reps ?? 0}',
          style: AppText.number(40,
              color: last?.targetReps != null &&
                      last!.reps >= last.targetReps!
                  ? c.mark
                  : c.ink),
        ),
        if (last?.targetReps != null)
          TextSpan(
            text: ' / ${last!.targetReps}',
            style: AppText.number(40, color: c.ink2),
          ),
      ]),
    );

    final stats = StatPair(
      left: StatCell(label: 'Repeticiones', value: repsValue),
      right: StatCell(
        label: 'Velocidad media',
        value: NumberWithUnit(
          value: velocity == null ? '—' : formatVelocity(velocity),
          unit: velocity == null ? null : 'm/s',
        ),
      ),
    );

    final weight = SizedBox(
      height: 96,
      child: Row(
        children: [
          const Expanded(child: AppLabel('Peso usado')),
          WeightStepper(
            valueKg: last?.weightKg,
            large: false,
            onChanged: workout.setLastWeight,
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 48,
            child: Row(
              children: [
                Expanded(
                  child: Text('Descanso',
                      style: AppText.text(20,
                          weight: FontWeight.w500, color: c.ink)),
                ),
                const SensorBadge(),
              ],
            ),
          ),
          if (workout.isFree && last != null)
            Text(
              '${workout.exercise.name} · serie ${last.setNumber}',
              style: AppText.text(16, color: c.ink2),
            ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      formatClock(
                        total == null ? workout.restElapsed : workout.restRemaining,
                      ),
                      style: AppText.number(200, height: 0.9, color: c.ink),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (total != null) ...[
                  ProgressTrack(value: workout.restElapsed / total),
                  const SizedBox(height: 10),
                  DefaultTextStyle(
                    style: AppText.text(13, color: c.ink3),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(formatClock(workout.restElapsed.clamp(0, total))),
                        Text(formatClock(total)),
                      ],
                    ),
                  ),
                ] else
                  const AppLabel('Tiempo de descanso',
                      textAlign: TextAlign.center),
              ],
            ),
          ),
          stats,
          weight,
          if (workout.isFree) ...[
            PrimaryButton(
              label: 'Siguiente serie',
              onPressed: workout.startNextSet,
            ),
            const SizedBox(height: 12),
            SecondaryButton(
              label: 'Cambiar ejercicio',
              onPressed: onChangeExercise,
            ),
            Center(
              child: TextAction(label: 'Terminar entrenamiento', onPressed: onEnd),
            ),
          ] else if (next != null) ...[
            Container(height: 1, color: c.line),
            const SizedBox(height: 24),
            const AppLabel('Sigue'),
            const SizedBox(height: 6),
            Text(
              '${next.exercise.name} · serie ${next.setNumber} de '
              '${next.totalSets}',
              style: AppText.text(20, weight: FontWeight.w500, color: c.ink),
            ),
            const SizedBox(height: 6),
            Text(
              '${next.targetReps} repeticiones · '
              '${next.weightKg == null ? 'peso corporal' : '${formatKg(next.weightKg!)} kg'}',
              style: AppText.text(16, color: c.ink2),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text('Empieza sola al terminar el descanso.',
                      style: AppText.text(13, color: c.ink3)),
                ),
                // Not in the mockups: skipping the rest is a common need.
                TextAction(
                  label: 'Empezar ya',
                  size: 14,
                  weight: FontWeight.w600,
                  color: c.ink,
                  onPressed: workout.startNextSet,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
