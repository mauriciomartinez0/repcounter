import uuid
from datetime import timedelta

from tests.conftest import auth, make_routine, now, register


def test_put_creates_and_replay_is_harmless(client, user):
    rid = str(uuid.uuid4())
    body = make_routine()
    first = client.put(f"/routines/{rid}", headers=user, json=body)
    assert first.status_code == 200
    assert first.json()["applied"] is True
    # El teléfono no supo si llegó y lo manda otra vez.
    again = client.put(f"/routines/{rid}", headers=user, json=body)
    assert again.status_code == 200
    routines = client.get("/routines", headers=user).json()["routines"]
    assert len(routines) == 1
    assert routines[0]["items"][0] == {
        "exerciseId": "bench-press", "sets": 4, "reps": 8, "weightKg": 60.0, "restSeconds": 120,
    }


def test_latest_edit_wins_between_phones(client, user):
    rid = str(uuid.uuid4())
    t0 = now() - timedelta(hours=2)
    client.put(f"/routines/{rid}", headers=user, json=make_routine(t0))

    # Teléfono A edita a las t0+60, teléfono B editó a las t0+30 pero sube después.
    client.put(f"/routines/{rid}", headers=user, json=make_routine(t0 + timedelta(minutes=60), name="Empuje A"))
    r = client.put(f"/routines/{rid}", headers=user, json=make_routine(t0 + timedelta(minutes=30), name="Empuje B"))
    assert r.status_code == 200
    assert r.json()["applied"] is False
    assert r.json()["routine"]["name"] == "Empuje A"


def test_delete_leaves_a_tombstone_for_other_phones(client, user):
    rid = str(uuid.uuid4())
    client.put(f"/routines/{rid}", headers=user, json=make_routine())
    sync = client.get("/routines", headers=user).json()
    cursor = sync["serverTime"]

    assert client.delete(f"/routines/{rid}", headers=user).status_code == 204
    assert client.delete(f"/routines/{rid}", headers=user).status_code == 204  # idempotente

    # Lista completa: ya no aparece.
    assert client.get("/routines", headers=user).json()["routines"] == []
    # Sincronización incremental: aparece como borrada.
    changed = client.get("/routines", headers=user, params={"since": cursor}).json()["routines"]
    assert [r["id"] for r in changed] == [rid]
    assert changed[0]["deletedAt"] is not None

    # Un teléfono atrasado que intenta editarla se entera de que se borró.
    r = client.put(f"/routines/{rid}", headers=user, json=make_routine(now()))
    assert r.status_code == 410


def test_cannot_touch_another_users_routine(client, user):
    rid = str(uuid.uuid4())
    client.put(f"/routines/{rid}", headers=user, json=make_routine())
    other = auth(register(client, email="otra@correo.com"))

    assert client.put(f"/routines/{rid}", headers=other, json=make_routine()).status_code == 409
    assert client.get(f"/routines/{rid}", headers=other).status_code == 404
    client.delete(f"/routines/{rid}", headers=other)
    assert client.get(f"/routines/{rid}", headers=user).json()["deletedAt"] is None


def test_rejects_unknown_exercises_and_future_clocks(client, user):
    rid = str(uuid.uuid4())
    bad = make_routine(items=[{"exerciseId": "no-existe", "sets": 3, "reps": 10, "restSeconds": 60}])
    r = client.put(f"/routines/{rid}", headers=user, json=bad)
    assert r.status_code == 422
    assert r.json()["error"]["exerciseIds"] == ["no-existe"]

    r = client.put(f"/routines/{rid}", headers=user, json=make_routine(now() + timedelta(days=3)))
    assert r.status_code == 422
    assert r.json()["error"]["code"] == "clock_skew"
