import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta

import psycopg

from tests.conftest import TEST_URL, auth, make_routine, make_session, now, register


def count_rows(session_id: str) -> tuple[int, int]:
    with psycopg.connect(TEST_URL) as conn:
        s = conn.execute("SELECT count(*) FROM workout_sessions WHERE id = %s", (session_id,)).fetchone()[0]
        r = conn.execute("SELECT count(*) FROM set_records WHERE session_id = %s", (session_id,)).fetchone()[0]
    return s, r


def test_retry_after_lost_response_does_not_duplicate(client, user):
    session = make_session()
    first = client.post("/sessions", headers=user, json=session)
    assert first.status_code == 201
    assert first.json()["status"] == "created"
    assert first.json()["session"]["volumeKg"] == 960.0

    # La respuesta se perdió; el teléfono reintenta la misma sesión.
    retry = client.post("/sessions", headers=user, json=session)
    assert retry.status_code == 200
    assert retry.json()["status"] == "duplicate"
    assert retry.json()["session"] == first.json()["session"]
    assert count_rows(session["id"]) == (1, 2)


def test_simultaneous_retries_store_once(client, user):
    session = make_session()
    with ThreadPoolExecutor(max_workers=4) as pool:
        codes = list(pool.map(lambda _: client.post("/sessions", headers=user, json=session).status_code, range(4)))
    assert sorted(codes) == [200, 200, 200, 201]
    assert count_rows(session["id"]) == (1, 2)


def test_same_id_from_another_user_is_a_conflict(client, user):
    session = make_session()
    client.post("/sessions", headers=user, json=session)
    other = auth(register(client, email="otra@correo.com"))
    r = client.post("/sessions", headers=other, json=session)
    assert r.status_code == 409
    assert r.json()["error"]["code"] == "id_conflict"


def test_routine_must_be_uploaded_first_but_may_be_deleted_later(client, user):
    rid = str(uuid.uuid4())
    r = client.post("/sessions", headers=user, json=make_session(routine_id=rid))
    assert r.status_code == 422
    assert r.json()["error"]["code"] == "unknown_routine"

    client.put(f"/routines/{rid}", headers=user, json=make_routine())
    client.delete(f"/routines/{rid}", headers=user)
    # Sesión hecha sin conexión antes de que la rutina se borrara.
    r = client.post("/sessions", headers=user, json=make_session(routine_id=rid))
    assert r.status_code == 201
    assert r.json()["session"]["routineId"] == rid


def test_batch_reports_each_session(client, user):
    stored = make_session()
    client.post("/sessions", headers=user, json=stored)
    fresh = make_session()
    unknown_exercise = make_session(sets=[{
        "exerciseId": "no-existe", "setNumber": 1, "reps": 5, "completedAt": now().isoformat(),
    }])
    malformed = {"id": str(uuid.uuid4()), "title": "", "sets": []}

    r = client.post("/sessions/batch", headers=user, json={
        "sessions": [stored, fresh, unknown_exercise, malformed],
    })
    assert r.status_code == 200
    results = r.json()["results"]
    assert [x["status"] for x in results] == ["duplicate", "created", "rejected", "rejected"]
    assert results[2]["error"]["code"] == "unknown_exercise"
    assert results[3]["error"]["code"] == "validation_error"
    # Los rechazos no deshicieron la que sí entró.
    assert count_rows(fresh["id"]) == (1, 2)
    assert count_rows(unknown_exercise["id"]) == (0, 0)


def test_history_pages_and_sync(client, user):
    base = now() - timedelta(days=10)
    ids = []
    for day in range(5):
        s = make_session(start=base + timedelta(days=day))
        ids.append(s["id"])
        client.post("/sessions", headers=user, json=s)

    page1 = client.get("/sessions", headers=user, params={"limit": 2}).json()
    page2 = client.get("/sessions", headers=user, params={"limit": 2, "cursor": page1["nextCursor"]}).json()
    page3 = client.get("/sessions", headers=user, params={"limit": 2, "cursor": page2["nextCursor"]}).json()
    got = [s["id"] for p in (page1, page2, page3) for s in p["sessions"]]
    assert got == list(reversed(ids))
    assert page3["nextCursor"] is None

    # Otro teléfono descarga lo que llegó desde su última sincronización.
    sync = client.get("/sessions/sync", headers=user, params={"since": (now() - timedelta(hours=1)).isoformat()}).json()
    assert {s["id"] for s in sync["sessions"]} == set(ids)
    assert sync["hasMore"] is False


def test_progress_and_summary(client, user):
    base = now() - timedelta(days=20)
    for day, kg in [(0, 55), (7, 57.5), (14, 60)]:
        sets = [{
            "exerciseId": "bench-press", "setNumber": 1, "reps": 8, "weightKg": kg,
            "meanVelocity": 0.4, "completedAt": (base + timedelta(days=day)).isoformat(),
        }]
        client.post("/sessions", headers=user, json=make_session(start=base + timedelta(days=day), sets=sets))

    p = client.get("/exercises/bench-press/progress", headers=user, params={"metric": "weight", "range": "4w"}).json()
    assert [pt["value"] for pt in p["points"]] == [55, 57.5, 60]
    assert p["best"]["value"] == 60
    assert p["change"] == 5
    assert round(p["average"], 2) == 57.5

    orm = client.get("/exercises/bench-press/progress", headers=user, params={"metric": "oneRepMax"}).json()
    assert round(orm["latest"]["value"], 1) == 76.0  # 60 × (1 + 8/30)

    summary = client.get("/me/exercise-summary", headers=user).json()
    assert summary == [{
        "exerciseId": "bench-press",
        "lastDoneAt": summary[0]["lastDoneAt"],
        "lastWeightKg": 60.0,
    }]


def test_deleting_the_account_removes_its_data(client):
    tokens = register(client)
    h = auth(tokens)
    session = make_session()
    client.post("/sessions", headers=h, json=session)
    client.request("DELETE", "/me", headers=h, json={"password": "12345678"})
    assert count_rows(session["id"]) == (0, 0)
