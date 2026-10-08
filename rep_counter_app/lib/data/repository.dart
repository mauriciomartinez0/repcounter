// Data access. Screens read from an in-memory cache synchronously and write
// through async methods. [LocalGymRepository] keeps everything on the phone;
// an API-backed repository only has to implement the same abstract methods.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'seed.dart';

abstract class GymRepository extends ChangeNotifier {
  Future<void> load();

  List<Exercise> get exercises;
  List<Routine> get routines;

  /// Newest first.
  List<WorkoutSession> get sessions;
  Set<String> get favoriteIds;

  Future<Routine> saveRoutine(Routine routine);
  Future<void> deleteRoutine(String id);
  Future<void> saveSession(WorkoutSession session);
  Future<void> toggleFavorite(String exerciseId);

  // Everything below is derived from the data above, so every implementation
  // shares it.

  Exercise? exercise(String id) {
    for (final e in exercises) {
      if (e.id == id) return e;
    }
    return null;
  }

  Routine? routine(String id) {
    for (final r in routines) {
      if (r.id == id) return r;
    }
    return null;
  }

  Future<Routine> duplicateRoutine(String id) {
    final original = routine(id)!;
    return saveRoutine(
      original.copyWith(id: '', name: '${original.name} (copia)'),
    );
  }

  /// Exercises done most recently, newest first.
  List<Exercise> recentExercises({int limit = 6}) {
    final ids = <String>[];
    for (final session in sessions) {
      for (final set in session.sets.reversed) {
        if (!ids.contains(set.exerciseId)) ids.add(set.exerciseId);
        if (ids.length >= limit) break;
      }
      if (ids.length >= limit) break;
    }
    return [for (final id in ids) ?exercise(id)];
  }

  List<Exercise> get favoriteExercises =>
      [for (final e in exercises) if (favoriteIds.contains(e.id)) e];

  /// Weight used the last time this exercise was done.
  double? lastWeight(String exerciseId) {
    for (final session in sessions) {
      for (final set in session.sets.reversed) {
        if (set.exerciseId == exerciseId && set.weightKg != null) {
          return set.weightKg;
        }
      }
    }
    return null;
  }

  /// The session of the same routine that came before [session].
  WorkoutSession? previousSession(WorkoutSession session) {
    if (session.routineId == null) return null;
    for (final s in sessions) {
      if (s.id != session.id &&
          s.routineId == session.routineId &&
          s.startedAt.isBefore(session.startedAt)) {
        return s;
      }
    }
    return null;
  }

  /// Exercises that have at least one set with a velocity reading, most
  /// recently done first.
  List<Exercise> exercisesWithVelocity() {
    final ids = <String>[];
    for (final session in sessions) {
      for (final set in session.sets) {
        if (set.meanVelocity != null && !ids.contains(set.exerciseId)) {
          ids.add(set.exerciseId);
        }
      }
    }
    return [for (final id in ids) ?exercise(id)];
  }

  /// Every session that included [exerciseId], oldest first, paired with its
  /// sets of that exercise.
  List<(WorkoutSession, List<SetRecord>)> historyFor(String exerciseId) {
    final result = <(WorkoutSession, List<SetRecord>)>[];
    for (final session in sessions.reversed) {
      final sets = [
        for (final s in session.sets)
          if (s.exerciseId == exerciseId) s,
      ];
      if (sets.isNotEmpty) result.add((session, sets));
    }
    return result;
  }
}

class LocalGymRepository extends GymRepository {
  LocalGymRepository({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  static const _kRoutines = 'repo.routines';
  static const _kSessions = 'repo.sessions';
  static const _kFavorites = 'repo.favorites';

  final DateTime Function() _clock;
  SharedPreferences? _prefs;

  List<Exercise> _exercises = const [];
  List<Routine> _routines = const [];
  List<WorkoutSession> _sessions = const [];
  Set<String> _favorites = {};

  @override
  List<Exercise> get exercises => _exercises;
  @override
  List<Routine> get routines => _routines;
  @override
  List<WorkoutSession> get sessions => _sessions;
  @override
  Set<String> get favoriteIds => _favorites;

  @override
  Future<void> load() async {
    _exercises = seedExercises;
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {
      _prefs = null; // Tests and unsupported platforms: memory only.
    }
    final prefs = _prefs;

    final routinesJson = prefs?.getString(_kRoutines);
    _routines = routinesJson == null
        ? List.of(seedRoutines)
        : [
            for (final r in jsonDecode(routinesJson) as List)
              Routine.fromJson(r as Map<String, dynamic>),
          ];

    final sessionsJson = prefs?.getString(_kSessions);
    _sessions = sessionsJson == null
        ? seedSessions(_clock())
        : [
            for (final s in jsonDecode(sessionsJson) as List)
              WorkoutSession.fromJson(s as Map<String, dynamic>),
          ];

    _favorites = prefs?.getStringList(_kFavorites)?.toSet() ??
        {'squat', 'deadlift', 'db-shoulder-press'};
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.setString(
      _kRoutines,
      jsonEncode([for (final r in _routines) r.toJson()]),
    );
    await prefs.setString(
      _kSessions,
      jsonEncode([for (final s in _sessions) s.toJson()]),
    );
    await prefs.setStringList(_kFavorites, _favorites.toList());
  }

  @override
  Future<Routine> saveRoutine(Routine routine) async {
    final saved = routine.id.isEmpty
        ? routine.copyWith(id: 'r-${_clock().microsecondsSinceEpoch}')
        : routine;
    final index = _routines.indexWhere((r) => r.id == saved.id);
    _routines = [..._routines];
    if (index < 0) {
      _routines.add(saved);
    } else {
      _routines[index] = saved;
    }
    notifyListeners();
    await _persist();
    return saved;
  }

  @override
  Future<void> deleteRoutine(String id) async {
    _routines = [for (final r in _routines) if (r.id != id) r];
    notifyListeners();
    await _persist();
  }

  @override
  Future<void> saveSession(WorkoutSession session) async {
    _sessions = [session, ..._sessions.where((s) => s.id != session.id)]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    notifyListeners();
    await _persist();
  }

  @override
  Future<void> toggleFavorite(String exerciseId) async {
    _favorites = {..._favorites};
    if (!_favorites.remove(exerciseId)) _favorites.add(exerciseId);
    notifyListeners();
    await _persist();
  }
}
