// Domain models. They serialize to JSON with the same shape the backend API
// is expected to use, so swapping the local repository for a remote one only
// changes where the JSON goes.

import '../theme/app_icons.dart';

enum MuscleGroup {
  chest('Pecho'),
  back('Espalda'),
  legs('Piernas'),
  shoulders('Hombros'),
  arms('Brazos'),
  core('Core');

  const MuscleGroup(this.label);
  final String label;
}

enum Equipment {
  barbell('Barra', AppIconKind.barbell),
  dumbbell('Mancuerna', AppIconKind.dumbbell),
  machine('Máquina', AppIconKind.machine),
  bodyweight('Peso corporal', AppIconKind.bodyweight),
  cable('Polea', AppIconKind.cable);

  const Equipment(this.label, this.icon);
  final String label;
  final AppIconKind icon;
}

/// Where the sensor goes. Also decides which counting profile the firmware
/// uses (see [Exercise.firmwareProfile]).
enum SensorPlacement {
  arm('Brazo', 'Antebrazo o muñeca', AppIconKind.placementArm),
  body('Cuerpo', 'Cintura o mochila', AppIconKind.placementBody),
  equipment('Equipo', 'Barra o máquina', AppIconKind.placementEquipment);

  const SensorPlacement(this.label, this.hint, this.icon);
  final String label;
  final String hint;
  final AppIconKind icon;
}

class Exercise {
  const Exercise({
    required this.id,
    required this.name,
    required this.muscleGroup,
    required this.equipment,
    required this.placement,
    required this.placementNote,
    this.firmwareProfile = 0,
    this.thresholdDegrees = 70,
    this.tutorialSteps = const [],
    this.tutorialSeconds = 0,
    this.videoUrl,
  });

  final String id;
  final String name;
  final MuscleGroup muscleGroup;
  final Equipment equipment;
  final SensorPlacement placement;

  /// "Sobre la barra, en el centro."
  final String placementNote;

  /// Exercise id the board understands (CMD_SET_EXERCISE). The current
  /// firmware knows 0 (sensor on the arm) and 1 (sensor on the body).
  final int firmwareProfile;

  /// Angle the movement has to pass for a rep to count.
  final int thresholdDegrees;

  final List<String> tutorialSteps;
  final int tutorialSeconds;
  final String? videoUrl;

  bool get hasTutorial => tutorialSteps.isNotEmpty || videoUrl != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'muscleGroup': muscleGroup.name,
        'equipment': equipment.name,
        'placement': placement.name,
        'placementNote': placementNote,
        'firmwareProfile': firmwareProfile,
        'thresholdDegrees': thresholdDegrees,
        'tutorialSteps': tutorialSteps,
        'tutorialSeconds': tutorialSeconds,
        'videoUrl': videoUrl,
      };

  factory Exercise.fromJson(Map<String, dynamic> j) => Exercise(
        id: j['id'] as String,
        name: j['name'] as String,
        muscleGroup: MuscleGroup.values.byName(j['muscleGroup'] as String),
        equipment: Equipment.values.byName(j['equipment'] as String),
        placement: SensorPlacement.values.byName(j['placement'] as String),
        placementNote: j['placementNote'] as String,
        firmwareProfile: j['firmwareProfile'] as int? ?? 0,
        thresholdDegrees: j['thresholdDegrees'] as int? ?? 70,
        tutorialSteps:
            (j['tutorialSteps'] as List? ?? const []).cast<String>().toList(),
        tutorialSeconds: j['tutorialSeconds'] as int? ?? 0,
        videoUrl: j['videoUrl'] as String?,
      );
}

/// One exercise inside a routine, with its plan.
class RoutineItem {
  const RoutineItem({
    required this.exerciseId,
    this.sets = 3,
    this.reps = 10,
    this.weightKg,
    this.restSeconds = 90,
  });

  final String exerciseId;
  final int sets;
  final int reps;

  /// Null means body weight.
  final double? weightKg;
  final int restSeconds;

  RoutineItem copyWith({
    int? sets,
    int? reps,
    double? Function()? weightKg,
    int? restSeconds,
  }) =>
      RoutineItem(
        exerciseId: exerciseId,
        sets: sets ?? this.sets,
        reps: reps ?? this.reps,
        weightKg: weightKg != null ? weightKg() : this.weightKg,
        restSeconds: restSeconds ?? this.restSeconds,
      );

  Map<String, dynamic> toJson() => {
        'exerciseId': exerciseId,
        'sets': sets,
        'reps': reps,
        'weightKg': weightKg,
        'restSeconds': restSeconds,
      };

  factory RoutineItem.fromJson(Map<String, dynamic> j) => RoutineItem(
        exerciseId: j['exerciseId'] as String,
        sets: j['sets'] as int,
        reps: j['reps'] as int,
        weightKg: (j['weightKg'] as num?)?.toDouble(),
        restSeconds: j['restSeconds'] as int,
      );
}

class Routine {
  const Routine({required this.id, required this.name, required this.items});

  final String id;
  final String name;
  final List<RoutineItem> items;

  /// Rough length: about a minute per set (work plus setup), the planned
  /// rest, and five minutes to warm up and move between stations.
  int get estimatedMinutes {
    var seconds = 300;
    for (final item in items) {
      seconds += item.sets * (60 + item.restSeconds);
    }
    final minutes = seconds / 60;
    return ((minutes / 5).round() * 5).clamp(5, 600);
  }

  Routine copyWith({String? id, String? name, List<RoutineItem>? items}) =>
      Routine(
        id: id ?? this.id,
        name: name ?? this.name,
        items: items ?? this.items,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'items': [for (final i in items) i.toJson()],
      };

  factory Routine.fromJson(Map<String, dynamic> j) => Routine(
        id: j['id'] as String,
        name: j['name'] as String,
        items: [
          for (final i in j['items'] as List)
            RoutineItem.fromJson(i as Map<String, dynamic>),
        ],
      );
}

/// One finished set, as counted by the sensor.
class SetRecord {
  const SetRecord({
    required this.exerciseId,
    required this.setNumber,
    required this.reps,
    required this.completedAt,
    this.targetReps,
    this.weightKg,
    this.meanVelocity,
    this.rangeDegrees,
  });

  final String exerciseId;
  final int setNumber;
  final int reps;
  final int? targetReps;
  final double? weightKg;

  /// Mean concentric velocity in m/s. Null when the sensor did not report it.
  final double? meanVelocity;

  /// Largest angle reached during the set.
  final double? rangeDegrees;
  final DateTime completedAt;

  double get volumeKg => (weightKg ?? 0) * reps;

  SetRecord copyWith({double? Function()? weightKg}) => SetRecord(
        exerciseId: exerciseId,
        setNumber: setNumber,
        reps: reps,
        targetReps: targetReps,
        weightKg: weightKg != null ? weightKg() : this.weightKg,
        meanVelocity: meanVelocity,
        rangeDegrees: rangeDegrees,
        completedAt: completedAt,
      );

  Map<String, dynamic> toJson() => {
        'exerciseId': exerciseId,
        'setNumber': setNumber,
        'reps': reps,
        'targetReps': targetReps,
        'weightKg': weightKg,
        'meanVelocity': meanVelocity,
        'rangeDegrees': rangeDegrees,
        'completedAt': completedAt.toIso8601String(),
      };

  factory SetRecord.fromJson(Map<String, dynamic> j) => SetRecord(
        exerciseId: j['exerciseId'] as String,
        setNumber: j['setNumber'] as int,
        reps: j['reps'] as int,
        targetReps: j['targetReps'] as int?,
        weightKg: (j['weightKg'] as num?)?.toDouble(),
        meanVelocity: (j['meanVelocity'] as num?)?.toDouble(),
        rangeDegrees: (j['rangeDegrees'] as num?)?.toDouble(),
        completedAt: DateTime.parse(j['completedAt'] as String),
      );
}

class WorkoutSession {
  const WorkoutSession({
    required this.id,
    required this.title,
    required this.startedAt,
    required this.endedAt,
    required this.sets,
    this.routineId,
    this.plannedExercises = 0,
  });

  final String id;
  final String? routineId;

  /// Routine name, or "Entrenamiento libre".
  final String title;
  final DateTime startedAt;
  final DateTime endedAt;
  final List<SetRecord> sets;

  /// How many exercises the routine had, for "5 de 5 ejercicios".
  final int plannedExercises;

  Duration get duration => endedAt.difference(startedAt);

  double get volumeKg => sets.fold(0, (sum, s) => sum + s.volumeKg);

  /// Exercise ids in the order they were first done.
  List<String> get exerciseIds {
    final seen = <String>[];
    for (final s in sets) {
      if (!seen.contains(s.exerciseId)) seen.add(s.exerciseId);
    }
    return seen;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'routineId': routineId,
        'title': title,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt.toIso8601String(),
        'plannedExercises': plannedExercises,
        'sets': [for (final s in sets) s.toJson()],
      };

  factory WorkoutSession.fromJson(Map<String, dynamic> j) => WorkoutSession(
        id: j['id'] as String,
        routineId: j['routineId'] as String?,
        title: j['title'] as String,
        startedAt: DateTime.parse(j['startedAt'] as String),
        endedAt: DateTime.parse(j['endedAt'] as String),
        plannedExercises: j['plannedExercises'] as int? ?? 0,
        sets: [
          for (final s in j['sets'] as List)
            SetRecord.fromJson(s as Map<String, dynamic>),
        ],
      );
}

class UserProfile {
  const UserProfile({required this.name, required this.email});

  final String name;
  final String email;

  Map<String, dynamic> toJson() => {'name': name, 'email': email};

  factory UserProfile.fromJson(Map<String, dynamic> j) =>
      UserProfile(name: j['name'] as String, email: j['email'] as String);
}
