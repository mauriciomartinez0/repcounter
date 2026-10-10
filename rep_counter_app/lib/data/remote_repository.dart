// The user's data from the API, usable without network.
//
// Every change is applied to the local copy first (the screen updates right
// away, even in a gym with no signal) and queued in an "outbox". Sync pushes
// the outbox and then pulls what changed on the server, in the order the API
// expects (see rep_counter_api/README.md):
//
//   catalog → routines → sessions → favorites → pull routines → pull sessions
//   → pull favorites
//
// The API makes retries safe: ids are generated here and uploading the same
// session twice stores it once. So a change only leaves the outbox when the
// server confirmed it or refused it for good.

import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import 'local_store.dart';
import 'models.dart';
import 'repository.dart';
import 'seed.dart';

/// A change waiting to reach the server.
class _Op {
  _Op(this.type, this.id, {this.on, this.ready = true});

  /// putRoutine, deleteRoutine, uploadSession, favorite.
  final String type;
  final String id;

  /// favorite: true to add, false to remove.
  final bool? on;

  /// uploadSession: false while the summary can still correct it.
  bool ready;

  Map<String, dynamic> toJson() =>
      {'type': type, 'id': id, 'on': on, 'ready': ready};

  factory _Op.fromJson(Map<String, dynamic> j) => _Op(
        j['type'] as String,
        j['id'] as String,
        on: j['on'] as bool?,
        ready: j['ready'] as bool? ?? true,
      );
}

/// Thrown when the user changed mid-sync; the rest of that sync is dropped.
class _UserChanged implements Exception {}

class RemoteGymRepository extends GymRepository {
  RemoteGymRepository({
    required this.api,
    required this.store,
    DateTime Function()? clock,
    this.debounce = const Duration(milliseconds: 800),
    this.retryEvery = const Duration(seconds: 30),
  }) : _clock = clock ?? DateTime.now;

  static const _batchSize = 50;
  static const _catalogFile = 'catalog.json';

  final ApiClient api;
  final LocalStore store;
  final DateTime Function() _clock;
  final Duration debounce;
  final Duration retryEvery;

  String? _userId;
  List<Exercise> _exercises = seedExercises;
  String? _catalogEtag;
  List<Routine> _routines = const [];
  List<WorkoutSession> _sessions = const [];
  Set<String> _favorites = {};
  List<_Op> _outbox = [];
  String? _routinesCursor;
  String? _sessionsCursor;

  SyncStatus _status = SyncStatus.idle;
  DateTime? _lastSyncedAt;
  String? _issue;
  Future<void>? _running;
  bool _again = false;
  Timer? _debounceTimer;
  Timer? _retryTimer;

  @override
  List<Exercise> get exercises => _exercises;
  @override
  List<Routine> get routines => _routines;
  @override
  List<WorkoutSession> get sessions => _sessions;
  @override
  Set<String> get favoriteIds => _favorites;
  @override
  SyncStatus get syncStatus => _status;
  @override
  int get pendingChanges => _outbox.length;
  @override
  DateTime? get lastSyncedAt => _lastSyncedAt;
  @override
  String? get syncIssue => _issue;

  // --- Local copy ---------------------------------------------------------

  String _file(String name) => 'users/$_userId/$name.json';

  Future<dynamic> _readJson(String name) async {
    final raw = await store.read(name);
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null; // A damaged file is refetched from the server.
    }
  }

  @override
  Future<void> load() async {
    // Catalog shared by all users. Until the first download, the copy that
    // ships with the app.
    final catalog = await _readJson(_catalogFile);
    if (catalog is Map) {
      _catalogEtag = catalog['etag'] as String?;
      _exercises = [
        for (final e in catalog['exercises'] as List)
          Exercise.fromJson(e as Map<String, dynamic>),
      ];
    }
    notifyListeners();
  }

  @override
  Future<void> switchUser(String? userId) async {
    if (userId == _userId) return;
    _debounceTimer?.cancel();
    _retryTimer?.cancel();
    _userId = userId;
    _routines = const [];
    _sessions = const [];
    _favorites = {};
    _outbox = [];
    _routinesCursor = null;
    _sessionsCursor = null;
    _issue = null;
    _lastSyncedAt = null;
    _status = SyncStatus.idle;

    if (userId != null) {
      final routines = await _readJson(_file('routines'));
      final sessions = await _readJson(_file('sessions'));
      final favorites = await _readJson(_file('favorites'));
      final outbox = await _readJson(_file('outbox'));
      final cursors = await _readJson(_file('cursors'));
      if (_userId != userId) return;
      _routines = [
        for (final r in routines as List? ?? const [])
          Routine.fromJson(r as Map<String, dynamic>),
      ];
      _sessions = [
        for (final s in sessions as List? ?? const [])
          WorkoutSession.fromJson(s as Map<String, dynamic>),
      ];
      _favorites = {...(favorites as List? ?? const []).cast<String>()};
      _outbox = [
        for (final o in outbox as List? ?? const [])
          _Op.fromJson(o as Map<String, dynamic>),
      ];
      // The app closed before "Listo": those workouts are final now.
      for (final op in _outbox) {
        op.ready = true;
      }
      if (cursors is Map) {
        _routinesCursor = cursors['routines'] as String?;
        _sessionsCursor = cursors['sessions'] as String?;
        final last = cursors['lastSyncedAt'] as String?;
        _lastSyncedAt = last == null ? null : DateTime.parse(last).toLocal();
      }
    }
    notifyListeners();
    if (userId != null) unawaited(sync());
  }

  @override
  Future<void> discardUserData() async {
    final userId = _userId;
    if (userId == null) return;
    await switchUser(null);
    await store.deleteAll('users/$userId');
  }

  Future<void> _saveRoutines() => store.write(
      _file('routines'), jsonEncode([for (final r in _routines) r.toJson()]));
  Future<void> _saveSessions() => store.write(
      _file('sessions'), jsonEncode([for (final s in _sessions) s.toJson()]));
  Future<void> _saveFavorites() =>
      store.write(_file('favorites'), jsonEncode(_favorites.toList()));
  Future<void> _saveOutbox() => store.write(
      _file('outbox'), jsonEncode([for (final o in _outbox) o.toJson()]));
  Future<void> _saveCursors() => store.write(
        _file('cursors'),
        jsonEncode({
          'routines': _routinesCursor,
          'sessions': _sessionsCursor,
          'lastSyncedAt': _lastSyncedAt?.toUtc().toIso8601String(),
        }),
      );

  // --- Changes made on this phone -------------------------------------------

  void _enqueue(_Op op, {bool Function(_Op existing)? replaces}) {
    if (replaces != null) _outbox.removeWhere(replaces);
    _outbox.add(op);
  }

  @override
  Future<Routine> saveRoutine(Routine routine) async {
    _requireUser();
    final saved = routine.copyWith(
      id: routine.id.isEmpty ? const Uuid().v4() : routine.id,
      editedAt: _clock(),
    );
    final index = _routines.indexWhere((r) => r.id == saved.id);
    _routines = [..._routines];
    if (index < 0) {
      _routines.add(saved);
    } else {
      _routines[index] = saved;
    }
    _enqueue(_Op('putRoutine', saved.id),
        replaces: (o) => o.type == 'putRoutine' && o.id == saved.id);
    notifyListeners();
    await Future.wait([_saveRoutines(), _saveOutbox()]);
    _scheduleSync();
    return saved;
  }

  @override
  Future<void> deleteRoutine(String id) async {
    _requireUser();
    _routines = [for (final r in _routines) if (r.id != id) r];
    _enqueue(_Op('deleteRoutine', id),
        replaces: (o) =>
            (o.type == 'putRoutine' || o.type == 'deleteRoutine') && o.id == id);
    notifyListeners();
    await Future.wait([_saveRoutines(), _saveOutbox()]);
    _scheduleSync();
  }

  /// Saves locally. The upload waits for [commitSession] so corrections on
  /// the summary go up together with the session.
  @override
  Future<void> saveSession(WorkoutSession session) async {
    _requireUser();
    _sessions = [session, ..._sessions.where((s) => s.id != session.id)]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final queued = _outbox
        .any((o) => o.type == 'uploadSession' && o.id == session.id);
    if (!queued) _enqueue(_Op('uploadSession', session.id, ready: false));
    notifyListeners();
    await Future.wait([_saveSessions(), _saveOutbox()]);
  }

  @override
  Future<void> commitSession(String sessionId) async {
    for (final op in _outbox) {
      if (op.type == 'uploadSession' && op.id == sessionId) op.ready = true;
    }
    await _saveOutbox();
    _scheduleSync(immediately: true);
  }

  @override
  Future<void> toggleFavorite(String exerciseId) async {
    _requireUser();
    _favorites = {..._favorites};
    final on = !_favorites.remove(exerciseId);
    if (on) _favorites.add(exerciseId);
    _enqueue(_Op('favorite', exerciseId, on: on),
        replaces: (o) => o.type == 'favorite' && o.id == exerciseId);
    notifyListeners();
    await Future.wait([_saveFavorites(), _saveOutbox()]);
    _scheduleSync();
  }

  void _requireUser() {
    if (_userId == null) throw StateError('No hay una cuenta activa.');
  }

  // --- Sync -------------------------------------------------------------------

  void _scheduleSync({bool immediately = false}) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(immediately ? Duration.zero : debounce, sync);
  }

  @override
  Future<void> sync() {
    if (_userId == null) return Future.value();
    if (_running != null) {
      // A change arrived mid-sync: run once more when this one ends.
      _again = true;
      return _running!;
    }
    return _running = _syncLoop().whenComplete(() => _running = null);
  }

  Future<void> _syncLoop() async {
    do {
      _again = false;
      await _syncOnce();
    } while (_again && _status == SyncStatus.idle);
  }

  Future<void> _syncOnce() async {
    final user = _userId;
    if (user == null) return;
    _retryTimer?.cancel();
    _status = SyncStatus.syncing;
    notifyListeners();
    void check() {
      if (_userId != user) throw _UserChanged();
    }

    try {
      await _pullCatalog();
      check();
      await _pushRoutines(check);
      await _pushSessions(check);
      await _pushFavorites(check);
      await _pullRoutines(check);
      await _pullSessions(check);
      await _pullFavorites(check);
      _status = SyncStatus.idle;
      _lastSyncedAt = _clock();
      await _saveCursors();
    } on _UserChanged {
      return;
    } on NetworkException {
      _status = SyncStatus.offline;
      _retryLater();
    } on ApiException catch (e) {
      if (_userId != user) return;
      // 401 here means the session ended; AuthController already reacted.
      _status = e.status == 401 ? SyncStatus.idle : SyncStatus.error;
      if (e.status != 401) {
        _issue = e.message;
        _retryLater();
      }
    }
    if (_userId == user) notifyListeners();
  }

  void _retryLater() {
    _retryTimer?.cancel();
    _retryTimer = Timer(retryEvery, sync);
  }

  Future<void> _pullCatalog() async {
    final response = await api.get(
      '/exercises',
      auth: false,
      headers: {if (_catalogEtag != null) 'If-None-Match': '"$_catalogEtag"'},
    );
    if (response.status == 304) return;
    final body = response.body as Map<String, dynamic>;
    _catalogEtag = body['version'] as String?;
    _exercises = [
      for (final e in body['exercises'] as List)
        Exercise.fromJson(e as Map<String, dynamic>),
    ];
    await store.write(
      _catalogFile,
      jsonEncode({'etag': _catalogEtag, 'exercises': body['exercises']}),
    );
    notifyListeners();
  }

  /// Takes [op] out of the queue and saves the queue right away, so a crash
  /// after a confirmed upload does not resend it (harmless, but wasteful).
  Future<void> _done(_Op op) async {
    _outbox.remove(op);
    await _saveOutbox();
  }

  void _refused(String what, ApiException e) {
    _issue = '$what: ${e.message}';
  }

  Future<void> _pushRoutines(void Function() check) async {
    for (final op in [..._outbox]) {
      if (op.type != 'putRoutine' && op.type != 'deleteRoutine') continue;
      check();
      if (op.type == 'deleteRoutine') {
        try {
          await api.delete('/routines/${op.id}');
        } on ApiException catch (e) {
          if (!e.isPermanent) rethrow;
        }
        check();
        await _done(op);
        continue;
      }
      final local = routine(op.id);
      if (local == null) {
        await _done(op);
        continue;
      }
      try {
        final response = await api.put('/routines/${op.id}', body: {
          'name': local.name,
          'items': [for (final i in local.items) i.toJson()],
          'editedAt': local.toJson()['editedAt'] ??
              _clock().toUtc().toIso8601String(),
        });
        check();
        final result = response.body as Map<String, dynamic>;
        if (result['applied'] == false) {
          // Another phone edited it later: keep that version.
          _replaceRoutine(
              Routine.fromJson(result['routine'] as Map<String, dynamic>));
        }
      } on ApiException catch (e) {
        check();
        if (e.status == 410) {
          // Deleted on another phone.
          _routines = [for (final r in _routines) if (r.id != op.id) r];
        } else if (e.isPermanent) {
          _refused('No se pudo guardar la rutina "${local.name}"', e);
        } else {
          rethrow;
        }
      }
      await _done(op);
      await _saveRoutines();
      notifyListeners();
    }
  }

  void _replaceRoutine(Routine routine) {
    final index = _routines.indexWhere((r) => r.id == routine.id);
    _routines = [..._routines];
    if (index < 0) {
      _routines.add(routine);
    } else {
      _routines[index] = routine;
    }
  }

  Future<void> _pushSessions(void Function() check) async {
    final ready = [
      for (final o in _outbox)
        if (o.type == 'uploadSession' && o.ready) o,
    ];
    for (var i = 0; i < ready.length; i += _batchSize) {
      final chunk = ready.sublist(i, (i + _batchSize).clamp(0, ready.length));
      final byId = {for (final s in _sessions) s.id: s};
      final sendable = [for (final op in chunk) if (byId[op.id] != null) op];
      for (final op in chunk) {
        if (byId[op.id] == null) await _done(op);
      }
      if (sendable.isEmpty) continue;
      final response = await api.post('/sessions/batch', body: {
        'sessions': [for (final op in sendable) byId[op.id]!.toJson()],
      });
      check();
      final results = (response.body as Map<String, dynamic>)['results'] as List;
      for (final r in results.cast<Map<String, dynamic>>()) {
        final op = sendable.firstWhere((o) => o.id == r['id'],
            orElse: () => _Op('', ''));
        if (op.type.isEmpty) continue;
        if (r['status'] == 'rejected') {
          final error = (r['error'] as Map?)?.cast<String, dynamic>() ?? {};
          final session = byId[op.id]!;
          _issue = 'No se pudo guardar el entrenamiento "${session.title}" del '
              '${session.startedAt.day}/${session.startedAt.month}: '
              '${error['message'] ?? 'datos inválidos'}';
        }
        await _done(op);
      }
      notifyListeners();
    }
  }

  Future<void> _pushFavorites(void Function() check) async {
    for (final op in [..._outbox]) {
      if (op.type != 'favorite') continue;
      check();
      try {
        if (op.on == true) {
          await api.put('/favorites/${op.id}');
        } else {
          await api.delete('/favorites/${op.id}');
        }
      } on ApiException catch (e) {
        if (!e.isPermanent) rethrow;
      }
      check();
      await _done(op);
    }
  }

  bool _pendingRoutine(String id) => _outbox
      .any((o) => (o.type == 'putRoutine' || o.type == 'deleteRoutine') && o.id == id);

  Future<void> _pullRoutines(void Function() check) async {
    final response = await api.get('/routines',
        query: {if (_routinesCursor != null) 'since': _routinesCursor!});
    check();
    final body = response.body as Map<String, dynamic>;
    final incoming = [
      for (final r in body['routines'] as List) r as Map<String, dynamic>,
    ];
    if (_routinesCursor == null) {
      // First sync on this phone: the server list, plus local routines that
      // have not reached it yet.
      final local = {for (final r in _routines) r.id: r};
      _routines = [
        for (final r in incoming)
          if (_pendingRoutine(r['id'] as String) && local.containsKey(r['id']))
            local[r['id']]!
          else
            Routine.fromJson(r),
        for (final r in local.values)
          if (_pendingRoutine(r.id) && !incoming.any((i) => i['id'] == r.id)) r,
      ];
    } else {
      for (final r in incoming) {
        final id = r['id'] as String;
        if (_pendingRoutine(id)) continue; // Local change goes up first.
        if (r['deletedAt'] != null) {
          _routines = [for (final x in _routines) if (x.id != id) x];
        } else {
          _replaceRoutine(Routine.fromJson(r));
        }
      }
    }
    _routinesCursor = body['serverTime'] as String;
    await _saveRoutines();
    notifyListeners();
  }

  Future<void> _pullSessions(void Function() check) async {
    var since = _sessionsCursor ?? '1970-01-01T00:00:00Z';
    var changed = false;
    while (true) {
      final response =
          await api.get('/sessions/sync', query: {'since': since});
      check();
      final body = response.body as Map<String, dynamic>;
      final incoming = [
        for (final s in body['sessions'] as List)
          WorkoutSession.fromJson(s as Map<String, dynamic>),
      ];
      if (incoming.isNotEmpty) {
        final ids = {for (final s in incoming) s.id};
        _sessions = [
          ...incoming,
          ..._sessions.where((s) => !ids.contains(s.id)),
        ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
        changed = true;
      }
      since = body['serverTime'] as String;
      if (body['hasMore'] != true) break;
    }
    _sessionsCursor = since;
    if (changed) {
      await _saveSessions();
      notifyListeners();
    }
  }

  Future<void> _pullFavorites(void Function() check) async {
    final response = await api.get('/favorites');
    check();
    final server = {...(response.body as List).cast<String>()};
    // Changes still in the queue win over the server list.
    for (final op in _outbox) {
      if (op.type != 'favorite') continue;
      if (op.on == true) {
        server.add(op.id);
      } else {
        server.remove(op.id);
      }
    }
    if (server.length != _favorites.length || !server.containsAll(_favorites)) {
      _favorites = server;
      await _saveFavorites();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }
}
