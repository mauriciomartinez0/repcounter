// End-to-end: the app's account and data layers against a real API.
//
// Needs the API running (see rep_counter_api/README.md):
//
//   API_TEST_URL=http://localhost:8000 flutter test test/api_integration_test.dart
//
// Without API_TEST_URL these tests are skipped.

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'package:rep_counter_app/api/api_client.dart';
import 'package:rep_counter_app/data/local_store.dart';
import 'package:rep_counter_app/data/models.dart';
import 'package:rep_counter_app/data/remote_repository.dart';
import 'package:rep_counter_app/data/repository.dart';
import 'package:rep_counter_app/data/session_controllers.dart';

final String? baseUrl = Platform.environment['API_TEST_URL'];

/// HTTP client whose network can be switched off, like a phone in a gym
/// basement.
class FlakyClient extends http.BaseClient {
  final _inner = http.Client();
  bool offline = false;
  int sent = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (offline) throw http.ClientException('sin red', request.url);
    sent++;
    return _inner.send(request);
  }
}

/// One phone: its own HTTP client, token storage and disk.
class Phone {
  Phone() {
    api = ApiClient(baseUrl: baseUrl!, tokens: MemoryTokenStore(), httpClient: net);
    auth = AuthController(api: api);
    repo = RemoteGymRepository(
      api: api,
      store: MemoryLocalStore(),
      debounce: const Duration(milliseconds: 10),
      retryEvery: const Duration(hours: 1),
    );
  }

  final net = FlakyClient();
  late final ApiClient api;
  late final AuthController auth;
  late final RemoteGymRepository repo;

  Future<void> signedIn() async {
    await repo.load();
    await repo.switchUser(auth.user!.id);
    await repo.sync();
  }
}

String uniqueEmail() =>
    'prueba-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}@correo.com';

WorkoutSession sessionFor(Routine routine) {
  final start = DateTime.now().subtract(const Duration(hours: 1));
  return WorkoutSession(
    id: const Uuid().v4(),
    routineId: routine.id,
    title: routine.name,
    startedAt: start,
    endedAt: start.add(const Duration(minutes: 45)),
    plannedExercises: 1,
    sets: [
      for (final (n, reps) in [(1, 12), (2, 10), (3, 9)])
        SetRecord(
          exerciseId: 'bench-press',
          setNumber: n,
          reps: reps,
          targetReps: 12,
          weightKg: 60,
          completedAt: start.add(Duration(minutes: 3 * n)),
        ),
    ],
  );
}

void main() {
  final skip = baseUrl == null ? 'Define API_TEST_URL para correr estas pruebas' : null;

  test('register stores the account and login finds it', () async {
    final email = uniqueEmail();
    final phone = Phone();
    await phone.auth.signUp('Camila', email, 'clave-segura-1');
    expect(phone.auth.signedIn, isTrue);
    expect(phone.auth.user!.email, email);

    // Another phone signs in with the same account.
    final other = Phone();
    await other.auth.signIn(email, 'clave-segura-1');
    expect(other.auth.user!.id, phone.auth.user!.id);

    // Wrong password: the API's message reaches the screen.
    await expectLater(
      Phone().auth.signIn(email, 'otra-clave-99'),
      throwsA(isA<AuthException>().having(
          (e) => e.message, 'message', 'Correo o contraseña incorrectos.')),
    );
    // Same email twice.
    await expectLater(
      Phone().auth.signUp('Otra', email, 'clave-segura-2'),
      throwsA(isA<AuthException>()
          .having((e) => e.message, 'message', contains('Ya existe'))),
    );
  }, skip: skip);

  test("a user's routines, workouts and favorites reach another phone",
      () async {
    final email = uniqueEmail();
    final a = Phone();
    await a.auth.signUp('Camila', email, 'clave-segura-1');
    await a.signedIn();

    // The catalog comes from the server and a new account starts empty.
    expect(a.repo.exercises, hasLength(32));
    expect(a.repo.routines, isEmpty);
    expect(a.repo.sessions, isEmpty);

    final routine = await a.repo.saveRoutine(const Routine(id: '', name: 'Empuje', items: [
      RoutineItem(exerciseId: 'bench-press', sets: 3, reps: 12, weightKg: 60, restSeconds: 120),
    ]));
    await a.repo.toggleFavorite('squat');
    final session = sessionFor(routine);
    await a.repo.saveSession(session);
    // Not uploaded until "Listo": the summary can still correct it.
    await a.repo.sync();
    expect(a.repo.pendingChanges, 1);
    await a.repo.commitSession(session.id);
    await a.repo.sync();
    expect(a.repo.pendingChanges, 0);
    expect(a.repo.syncStatus, SyncStatus.idle);

    final b = Phone();
    await b.auth.signIn(email, 'clave-segura-1');
    await b.signedIn();
    expect(b.repo.routines.map((r) => r.name), ['Empuje']);
    expect(b.repo.favoriteIds, {'squat'});
    expect(b.repo.sessions, hasLength(1));
    final got = b.repo.sessions.single;
    expect(got.id, session.id);
    expect([for (final s in got.sets) s.reps], [12, 10, 9]);
    // Dates come back as the same instant.
    expect(got.startedAt.isAtSameMomentAs(session.startedAt), isTrue);

    // A different user sees none of it.
    final c = Phone();
    await c.auth.signUp('Otra', uniqueEmail(), 'clave-segura-3');
    await c.signedIn();
    expect(c.repo.routines, isEmpty);
    expect(c.repo.sessions, isEmpty);
    expect(c.repo.favoriteIds, isEmpty);
  }, skip: skip);

  test('without signal, changes wait and upload once when it returns',
      () async {
    final email = uniqueEmail();
    final a = Phone();
    await a.auth.signUp('Camila', email, 'clave-segura-1');
    await a.signedIn();

    a.net.offline = true;
    final routine = await a.repo.saveRoutine(
        const Routine(id: '', name: 'Pierna', items: []));
    final session = sessionFor(routine);
    await a.repo.saveSession(session);
    await a.repo.commitSession(session.id);
    await a.repo.sync();
    expect(a.repo.syncStatus, SyncStatus.offline);
    expect(a.repo.pendingChanges, 2);
    // The screen already shows them.
    expect(a.repo.routines.map((r) => r.name), contains('Pierna'));

    a.net.offline = false;
    await a.repo.sync();
    expect(a.repo.syncStatus, SyncStatus.idle);
    expect(a.repo.pendingChanges, 0);

    // Simulate a response lost after the server saved: send it again.
    final response = await a.api.post('/sessions/batch', body: {
      'sessions': [session.toJson()],
    });
    expect((response.body as Map)['results'][0]['status'], 'duplicate');

    final b = Phone();
    await b.auth.signIn(email, 'clave-segura-1');
    await b.signedIn();
    expect(b.repo.sessions, hasLength(1));
  }, skip: skip);

  test('a routine edited on two phones keeps the latest edit', () async {
    final email = uniqueEmail();
    final a = Phone();
    await a.auth.signUp('Camila', email, 'clave-segura-1');
    await a.signedIn();
    final b = Phone();
    await b.auth.signIn(email, 'clave-segura-1');
    await b.signedIn();

    final routine = await a.repo.saveRoutine(
        const Routine(id: '', name: 'Tirón', items: []));
    await a.repo.sync();
    await b.repo.sync();
    expect(b.repo.routine(routine.id)?.name, 'Tirón');

    // Both edit offline; B edits last.
    a.net.offline = true;
    b.net.offline = true;
    await a.repo.saveRoutine(routine.copyWith(name: 'Tirón A'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await b.repo.saveRoutine(routine.copyWith(name: 'Tirón B'));
    // A uploads after B, yet B's later edit stays.
    b.net.offline = false;
    await b.repo.sync();
    a.net.offline = false;
    await a.repo.sync();
    expect(a.repo.routine(routine.id)?.name, 'Tirón B');

    // Deleting on B removes it from A at the next sync.
    await b.repo.deleteRoutine(routine.id);
    await b.repo.sync();
    await a.repo.sync();
    expect(a.repo.routine(routine.id), isNull);
  }, skip: skip);

  test('an expired access token renews itself; a dead session signs out',
      () async {
    final phone = Phone();
    await phone.auth.signUp('Camila', uniqueEmail(), 'clave-segura-1');
    final tokens = (await phone.api.tokens.read())!;

    // Access token "expired" on the phone's clock: renewed before the call.
    await phone.api.tokens.write(Tokens(
      access: tokens.access,
      refresh: tokens.refresh,
      accessExpiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
    ));
    final me = await phone.api.get('/me');
    expect((me.body as Map)['email'], phone.auth.user!.email);
    final renewed = (await phone.api.tokens.read())!;
    expect(renewed.refresh, isNot(tokens.refresh));

    // The server forgets the session (e.g. "cerrar sesión en todos lados").
    await phone.api.post('/auth/logout-all');
    await phone.api.tokens.write(Tokens(
      access: 'vencido',
      refresh: renewed.refresh,
      accessExpiresAt: DateTime.now().add(const Duration(minutes: 10)),
    ));
    await expectLater(phone.api.get('/me'), throwsA(isA<ApiException>()));
    expect(phone.auth.signedIn, isFalse);
    expect(phone.auth.sessionExpired, isTrue);
  }, skip: skip);
}
