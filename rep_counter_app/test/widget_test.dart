import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rep_counter_app/api/api_client.dart';
import 'package:rep_counter_app/app.dart';
import 'package:rep_counter_app/app_scope.dart';
import 'package:rep_counter_app/data/models.dart';
import 'package:rep_counter_app/data/repository.dart';
import 'package:rep_counter_app/data/session_controllers.dart';
import 'package:rep_counter_app/screens/workout/summary_screen.dart';
import 'package:rep_counter_app/sensor/sensor_service.dart';
import 'package:rep_counter_app/util/format.dart';
import 'package:rep_counter_app/workout/workout_controller.dart';

Future<AppServices> _services() async {
  SharedPreferences.setMockInitialValues({});
  final services = AppServices(
    repository: LocalGymRepository(clock: () => DateTime(2026, 10, 7)),
    auth: AuthController(
      api: ApiClient(baseUrl: 'http://localhost', tokens: MemoryTokenStore()),
    ),
    settings: SettingsController(),
    sensor: SimulatedSensorService(),
  );
  await services.load();
  return services;
}

void main() {
  test('Spanish number formatting', () {
    expect(formatNumber(3660), '3.660');
    expect(formatNumber(52.5, decimals: 1), '52,5');
    expect(formatNumber(60.0, decimals: 1), '60');
    expect(formatVelocity(0.46), '0,46');
    expect(formatSigned(180), '+180');
    expect(formatSigned(-3), '−3');
    expect(formatClock(84), '1:24');
    expect(formatDay(DateTime(2026, 10, 4)), 'Dom 4 oct');
  });

  test('DeviceState parses the optional velocity bytes', () {
    final base = [5, 0, 0x6C, 0x02, 1, 0x03];
    final old = DeviceState.parse(base)!;
    expect(old.repCount, 5);
    expect(old.angleDegrees, 62.0);
    expect(old.referenceCaptured, isTrue);
    expect(old.lastRepVelocity, isNull);

    final withVelocity = DeviceState.parse([...base, 0xCC, 0x01])!;
    expect(withVelocity.lastRepVelocity, closeTo(0.46, 0.001));
  });

  test('Routine JSON round trip', () {
    const routine = Routine(id: 'r', name: 'Empuje', items: [
      RoutineItem(exerciseId: 'bench-press', sets: 4, reps: 8, weightKg: 60),
      RoutineItem(exerciseId: 'dips'),
    ]);
    final copy = Routine.fromJson(routine.toJson());
    expect(copy.name, 'Empuje');
    expect(copy.items.first.weightKg, 60);
    expect(copy.items.last.weightKg, isNull);
  });

  test('Routine workout walks sets, rests and finishes', () async {
    final services = await _services();
    final repo = services.repository;
    final sensor = _FakeSensor();
    const routine = Routine(id: 'r-test', name: 'Prueba', items: [
      RoutineItem(exerciseId: 'bench-press', sets: 2, reps: 3, weightKg: 60,
          restSeconds: 30),
      RoutineItem(exerciseId: 'dips', sets: 1, reps: 5, restSeconds: 30),
    ]);
    final workout = WorkoutController.routine(
      repository: repo,
      sensor: sensor,
      routine: routine,
    )..start();

    expect(workout.phase, WorkoutPhase.calibrating);
    sensor.emit(captured: false);
    sensor.emit(captured: true);
    expect(workout.phase, WorkoutPhase.counting);

    sensor.emit(reps: 3, velocity: 0.5);
    expect(workout.targetReached, isTrue);
    workout.finishSet();
    expect(workout.phase, WorkoutPhase.resting);
    expect(workout.next!.setNumber, 2);

    workout.setLastWeight(62.5);
    expect(workout.lastRecord!.weightKg, 62.5);
    expect(workout.next!.weightKg, 62.5);

    workout.startNextSet();
    expect(workout.phase, WorkoutPhase.counting);
    sensor.emit(reps: 3);
    workout.finishSet();
    expect(workout.next!.exercise.id, 'dips');

    workout.startNextSet();
    expect(workout.phase, WorkoutPhase.calibrating);
    sensor.emit(captured: false);
    sensor.emit(captured: true);
    sensor.emit(reps: 5);
    workout.finishSet();
    expect(workout.phase, WorkoutPhase.finished);

    final session = await workout.finish();
    expect(session!.sets, hasLength(3));
    expect(session.volumeKg, 62.5 * 3 + 62.5 * 3);
    expect(repo.sessions.first.id, session.id);
    workout.dispose();
  });

  group('SetsDescription', () {
    final t = DateTime(2026, 10, 4);
    SetRecord set(int n, int reps, double? kg, {int? target = 12}) => SetRecord(
          exerciseId: 'x', setNumber: n, reps: reps, weightKg: kg,
          targetReps: target, completedAt: t);

    test('all sets as planned read like the plan', () {
      final d = SetsDescription([for (var n = 1; n <= 4; n++) set(n, 12, 60)]);
      expect(d.compact, isTrue);
      expect(d.text, '4 × 12 · 60 kg');
    });

    test('a drop-off lists every set', () {
      final d = SetsDescription([set(1, 12, 60), set(2, 10, 60), set(3, 9, 60), set(4, 8, 60)]);
      expect(d.compact, isFalse);
      expect(d.text, '60 kg: 12, 10, 9, 8');
      expect(d.missedTarget, isTrue);
      expect(d.target, 12);
    });

    test('weight changes start a new group', () {
      final d = SetsDescription([set(1, 12, 60), set(2, 10, 60), set(3, 10, 55), set(4, 9, 55)]);
      expect(d.text, '60 kg: 12, 10 · 55 kg: 10, 9');
    });

    test('same reps but all short of the target are not hidden', () {
      final d = SetsDescription([set(1, 10, null), set(2, 10, null)]);
      expect(d.compact, isFalse);
      expect(d.text, 'corporal: 10, 10');
    });
  });

  test('Short and zero-rep sets are kept and can be corrected', () async {
    final services = await _services();
    final sensor = _FakeSensor();
    const routine = Routine(id: 'r-short', name: 'Prueba', items: [
      RoutineItem(exerciseId: 'bench-press', sets: 3, reps: 12, weightKg: 60,
          restSeconds: 30),
    ]);
    final workout = WorkoutController.routine(
      repository: services.repository, sensor: sensor, routine: routine)
      ..start();
    sensor.emit(captured: false);
    sensor.emit(captured: true);

    sensor.emit(reps: 12);
    workout.finishSet();
    workout.startNextSet();
    sensor.emit(reps: 9);
    workout.finishSet();
    expect(workout.lastRecord!.reps, 9);
    // The sensor missed one; the user fixes it during the rest.
    workout.setLastReps(10);
    expect(workout.lastRecord!.reps, 10);

    workout.startNextSet();
    workout.finishSet(); // gave up without a rep
    expect(workout.phase, WorkoutPhase.finished);

    final session = (await workout.finish())!;
    expect([for (final s in session.sets) s.reps], [12, 10, 0]);
    expect(session.volumeKg, 60.0 * 22);
    workout.dispose();
  });

  testWidgets('Starts on login when signed out', (tester) async {
    final services = await tester.runAsync(_services);
    await tester.pumpWidget(RepCounterApp(services: services!));
    expect(find.text('Inicia sesión'), findsOneWidget);
    expect(find.text('Entrar'), findsOneWidget);
  });
}

/// Sensor that only reports what the test tells it to.
class _FakeSensor extends SensorService {
  DeviceState _state = DeviceState.empty;
  int _reps = 0;
  bool _captured = false;

  @override
  SensorStatus get status => SensorStatus.ready;
  @override
  SensorFailure? get failure => null;
  @override
  String get detail => '';
  @override
  DeviceState get state => _state;

  void emit({int? reps, bool? captured, double? velocity}) {
    _reps = reps ?? _reps;
    _captured = captured ?? _captured;
    _state = DeviceState(
      repCount: _reps,
      angleDegrees: 0,
      exerciseId: 0,
      inUpPhase: false,
      referenceCaptured: _captured,
      lastRepVelocity: velocity,
    );
    notifyListeners();
  }

  @override
  Future<void> connect() async {}
  @override
  Future<void> cancel() async {}
  @override
  Future<void> setExercise(int firmwareProfile) async {}
  @override
  Future<void> resetCount() async => emit(reps: 0);
  @override
  Future<void> rezero() async {}
}
