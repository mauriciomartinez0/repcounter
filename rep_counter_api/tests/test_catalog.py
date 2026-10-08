import psycopg

from tests.conftest import TEST_URL


def test_catalog_matches_the_app_seed(client):
    r = client.get("/exercises")
    assert r.status_code == 200
    exercises = {e["id"]: e for e in r.json()["exercises"]}
    assert len(exercises) == 32
    bench = exercises["bench-press"]
    assert bench["placement"] == "equipment"
    assert bench["tutorialSeconds"] == 48
    assert len(bench["tutorialSteps"]) == 4
    assert exercises["push-up"]["firmwareProfile"] == 1


def test_catalog_etag_and_304(client):
    r = client.get("/exercises")
    etag = r.headers["etag"]
    assert r.json()["version"] == etag.strip('"')

    r = client.get("/exercises", headers={"If-None-Match": etag})
    assert r.status_code == 304
    assert r.content == b""

    # Cambiar un paso del tutorial cambia la versión.
    with psycopg.connect(TEST_URL, autocommit=True) as conn:
        conn.execute(
            "UPDATE tutorial_steps SET body = 'Baja la barra al pecho.' "
            "WHERE exercise_id = 'bench-press' AND position = 2"
        )
    r = client.get("/exercises", headers={"If-None-Match": etag})
    assert r.status_code == 200
    assert r.headers["etag"] != etag


def test_favorites_are_idempotent(client, user):
    assert client.put("/favorites/squat", headers=user).status_code == 204
    assert client.put("/favorites/squat", headers=user).status_code == 204
    assert client.put("/favorites/deadlift", headers=user).status_code == 204
    assert client.get("/favorites", headers=user).json() == ["squat", "deadlift"]

    assert client.delete("/favorites/squat", headers=user).status_code == 204
    assert client.delete("/favorites/squat", headers=user).status_code == 204
    assert client.get("/favorites", headers=user).json() == ["deadlift"]

    r = client.put("/favorites/no-existe", headers=user)
    assert r.status_code == 404
