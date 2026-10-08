// State of a workout in progress: which exercise and set comes next, what the
// sensor counted, and the rest timer between sets. The screens in
// workout_flow_screen.dart only render this.

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../sensor/sensor_service.dart';

enum WorkoutPhase { calibrating, counting, resting, finished }

/// What the next set will be, for the "Sigue" block on the rest screen.
class PlannedSet {
  const PlannedSet({
    required this.exercise,
    required this.setNumber,
    this.totalSets,
    this.targetReps,
    this.weightKg,
  });

  final Exercise exercise;
  final int setNumber;
  final int? totalSets;
  final int? targetReps;
  final double? weightKg;
}

class WorkoutController extends ChangeNotifier {
  WorkoutController.routine({
    required this.repository,
    required this.sensor,
    required Routine this.routine,
    DateTime Function()? clock,
  })  : _clock = clock ?? DateTime.now,
        assert(routine.items.isNotEmpty) {
    _exercise = repository.exercise(routine!.items.first.exerciseId)!;
    _startedAt = _clock();
  }

  WorkoutController.free({
    required this.repository,
    required this.sensor,
    required Exercise exercise,
    double? weightKg,
    DateTime Function()? clock,
  })  : routine = null,
        _clock = clock ?? DateTime.now {
    _exercise = exercise;
    _freeWeight = weightKg;
    _startedAt = _clock();
  }

  /// Seconds without a new rep, once the target is reached, before the set
  /// closes on its own.
  static const autoFinishDelay = Duration(seconds: 3);

  final GymRepository repository;
  final SensorService sensor;
  final Routine? routine;
  final DateTime Function() _clock;

  late final DateTime _startedAt;
  late Exercise _exercise;
  final List<SetRecord> _records = [];

  WorkoutPhase _phase = WorkoutPhase.calibrating;
  int _itemIndex = 0;
  int _setNumber = 1;

  /// Weight changes made during the workout, per routine item.
  final Map<int, double?> _weightOverrides = {};
  double? _freeWeight;

  // Live tracking of the current set.
  int _lastRepCount = 0;
  double _maxAngle = 0;
  final List<double> _velocities = [];
  DateTime? _calibrationStartedAt;
  bool _sawUncalibrated = false;
  Timer? _autoFinish;
  Timer? _calibrationFallback;

  // Rest.
  DateTime? _restStartedAt;
  Timer? _restTicker;
  PlannedSet? _next;

  bool _started = false;
  bool _disposed = false;

  bool get isFree => routine == null;
  WorkoutPhase get phase => _phase;
  Exercise get exercise => _exercise;
  int get setNumber => _setNumber;
  DateTime get startedAt => _startedAt;
  List<SetRecord> get records => List.unmodifiable(_records);
  SetRecord? get lastRecord => _records.isEmpty ? null : _records.last;
  PlannedSet? get next => _next;

  RoutineItem? get item => routine?.items[_itemIndex];
  int? get totalSets => item?.sets;
  int? get targetReps => item?.reps;

  double? get weightKg => isFree
      ? _freeWeight
      : (_weightOverrides.containsKey(_itemIndex)
          ? _weightOverrides[_itemIndex]
          : item!.weightKg);

  int get reps => max(0, sensor.state.repCount);
  bool get targetReached => targetReps != null && reps >= targetReps!;

  /// 0–1 while calibrating; the board does not report progress, so this is
  /// time-based and waits at 90 % until the board confirms.
  double get calibrationProgress {
    final start = _calibrationStartedAt;
    if (start == null) return 0;
    final elapsed = _clock().difference(start).inMilliseconds / 1500;
    return min(0.9, elapsed);
  }

  /// Seconds since the rest started.
  int get restElapsed {
    final start = _restStartedAt;
    if (start == null) return 0;
    return _clock().difference(start).inSeconds;
  }

  /// Planned rest of the set just finished; null in free training.
  int? get restTotal {
    if (isFree || _records.isEmpty) return null;
    return routine!.items[_restItemIndex].restSeconds;
  }

  int _restItemIndex = 0;

  int get restRemaining => max(0, (restTotal ?? 0) - restElapsed);

  /// Mean velocity of the last finished set.
  double? get lastSetVelocity => lastRecord?.meanVelocity;

  void start() {
    if (_started) return;
    _started = true;
    sensor.addListener(_onSensor);
    _beginExercise();
  }

  void _beginExercise() {
    _phase = WorkoutPhase.calibrating;
    _calibrationStartedAt = _clock();
    _sawUncalibrated = false;
    _resetTracking();
    sensor.setExercise(_exercise.firmwareProfile);
    sensor.rezero();
    // If the board recaptures so fast that we never see it uncalibrated,
    // trust its flag after a short wait.
    _calibrationFallback?.cancel();
    _calibrationFallback = Timer(const Duration(seconds: 2), () {
      _sawUncalibrated = true;
      _onSensor();
    });
    _notify();
  }

  void _resetTracking() {
    _lastRepCount = 0;
    _maxAngle = 0;
    _velocities.clear();
    _autoFinish?.cancel();
  }

  void _onSensor() {
    if (_disposed) return;
    final state = sensor.state;
    switch (_phase) {
      case WorkoutPhase.calibrating:
        if (!state.referenceCaptured) _sawUncalibrated = true;
        if (_sawUncalibrated && state.referenceCaptured) {
          _calibrationFallback?.cancel();
          // Change phase before resetting: the reset notifies right back.
          _phase = WorkoutPhase.counting;
          _resetTracking();
          sensor.resetCount();
        }
      case WorkoutPhase.counting:
        _maxAngle = max(_maxAngle, state.angleDegrees);
        if (state.repCount > _lastRepCount) {
          _lastRepCount = state.repCount;
          final v = state.lastRepVelocity;
          if (v != null) _velocities.add(v);
          if (targetReached) {
            _autoFinish?.cancel();
            _autoFinish = Timer(autoFinishDelay, finishSet);
          }
        } else if (state.repCount < _lastRepCount) {
          // The board was reset (button or reconnect).
          _resetTracking();
        }
      case WorkoutPhase.resting:
      case WorkoutPhase.finished:
        break;
    }
    _notify();
  }

  /// "Reiniciar": start the current set over.
  Future<void> restartSet() async {
    _resetTracking();
    await sensor.resetCount();
    _notify();
  }

  /// Close the current set and move to rest, or to the end of the workout.
  void finishSet() {
    if (_phase != WorkoutPhase.counting) return;
    _autoFinish?.cancel();
    final reps = this.reps;
    if (reps > 0) {
      _records.add(SetRecord(
        exerciseId: _exercise.id,
        setNumber: _setNumber,
        reps: reps,
        targetReps: targetReps,
        weightKg: weightKg,
        meanVelocity: _velocities.isEmpty
            ? null
            : _velocities.reduce((a, b) => a + b) / _velocities.length,
        rangeDegrees: _maxAngle > 0 ? _maxAngle : null,
        completedAt: _clock(),
      ));
    }
    _restItemIndex = _itemIndex;

    _next = _planNext();
    if (_next == null) {
      _phase = WorkoutPhase.finished;
      _notify();
      return;
    }
    _phase = WorkoutPhase.resting;
    _restStartedAt = _clock();
    _restTicker?.cancel();
    _restTicker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!isFree && restRemaining <= 0) {
        startNextSet();
      } else {
        _notify();
      }
    });
    _notify();
  }

  PlannedSet? _planNext() {
    final routine = this.routine;
    if (routine == null) {
      return PlannedSet(
        exercise: _exercise,
        setNumber: _setNumber + 1,
        weightKg: _freeWeight,
      );
    }
    final current = routine.items[_itemIndex];
    if (_setNumber < current.sets) {
      return PlannedSet(
        exercise: _exercise,
        setNumber: _setNumber + 1,
        totalSets: current.sets,
        targetReps: current.reps,
        weightKg: weightKg,
      );
    }
    if (_itemIndex + 1 < routine.items.length) {
      final nextItem = routine.items[_itemIndex + 1];
      final nextExercise = repository.exercise(nextItem.exerciseId);
      if (nextExercise == null) return null;
      return PlannedSet(
        exercise: nextExercise,
        setNumber: 1,
        totalSets: nextItem.sets,
        targetReps: nextItem.reps,
        weightKg: nextItem.weightKg,
      );
    }
    return null;
  }

  /// End the rest and start the planned set. Recalibrates when the
  /// exercise changes, since the sensor probably moved.
  void startNextSet() {
    if (_phase != WorkoutPhase.resting) return;
    _restTicker?.cancel();
    _restStartedAt = null;
    final next = _next!;
    _next = null;
    final sameExercise = next.exercise.id == _exercise.id;
    // In a routine, set 1 always means the next item, even if it repeats
    // the same exercise.
    if (!isFree && next.setNumber == 1) _itemIndex++;
    _setNumber = next.setNumber;
    _exercise = next.exercise;
    if (sameExercise) {
      _phase = WorkoutPhase.counting;
      _resetTracking();
      sensor.resetCount();
      _notify();
    } else {
      _beginExercise();
    }
  }

  /// Free training: switch exercise during the rest.
  void changeExercise(Exercise exercise) {
    _restTicker?.cancel();
    _restStartedAt = null;
    _next = null;
    _exercise = exercise;
    _setNumber = 1;
    _freeWeight = repository.lastWeight(exercise.id);
    _beginExercise();
  }

  /// "Peso usado" on the rest screen corrects the set just done and carries
  /// over to the following sets of the same exercise.
  void setLastWeight(double? kg) {
    if (_records.isEmpty) return;
    final last = _records.removeLast();
    _records.add(last.copyWith(weightKg: () => kg));
    if (last.exerciseId == _exercise.id) {
      if (isFree) {
        _freeWeight = kg;
      } else {
        _weightOverrides[_itemIndex] = kg;
      }
    }
    final next = _next;
    if (next != null && next.exercise.id == last.exerciseId) {
      _next = PlannedSet(
        exercise: next.exercise,
        setNumber: next.setNumber,
        totalSets: next.totalSets,
        targetReps: next.targetReps,
        weightKg: kg,
      );
    }
    _notify();
  }

  /// Ends the workout. Returns the saved session, or null when no set was
  /// completed.
  Future<WorkoutSession?> finish() async {
    // A set in progress with reps counts.
    if (_phase == WorkoutPhase.counting && reps > 0) finishSet();
    _phase = WorkoutPhase.finished;
    _stopTimers();
    sensor.removeListener(_onSensor);
    if (_records.isEmpty) return null;
    final session = WorkoutSession(
      id: 's-${_startedAt.microsecondsSinceEpoch}',
      routineId: routine?.id,
      title: routine?.name ?? 'Entrenamiento libre',
      startedAt: _startedAt,
      endedAt: _clock(),
      plannedExercises: routine?.items.length ?? 0,
      sets: List.of(_records),
    );
    await repository.saveSession(session);
    return session;
  }

  void _stopTimers() {
    _autoFinish?.cancel();
    _restTicker?.cancel();
    _calibrationFallback?.cancel();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopTimers();
    sensor.removeListener(_onSensor);
    super.dispose();
  }
}
