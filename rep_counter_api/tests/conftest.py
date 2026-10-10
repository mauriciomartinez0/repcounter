"""Las pruebas usan una base aparte (repcounter_test) en el mismo servidor de
PostgreSQL, recreada desde las migraciones en cada corrida."""

import os
import uuid
from datetime import UTC, datetime, timedelta

import psycopg
import pytest

ADMIN_URL = os.environ.get(
    "TEST_ADMIN_DATABASE_URL", "postgresql://repcounter:repcounter@localhost:55432/repcounter"
)
TEST_DB = "repcounter_test"
TEST_URL = ADMIN_URL.rsplit("/", 1)[0] + "/" + TEST_DB

os.environ["DATABASE_URL"] = TEST_URL
os.environ["APP_ENV"] = "dev"
# Las pruebas registran muchas cuentas desde la misma IP; el límite se prueba
# aparte en test_auth.py.
os.environ["RATE_LIMIT_ENABLED"] = "false"

from fastapi.testclient import TestClient  # noqa: E402

from app.config import get_settings  # noqa: E402
from app.main import app  # noqa: E402
from app.migrate import migrate  # noqa: E402


@pytest.fixture(scope="session", autouse=True)
def database():
    with psycopg.connect(ADMIN_URL, autocommit=True) as conn:
        conn.execute(f"DROP DATABASE IF EXISTS {TEST_DB} WITH (FORCE)")
        conn.execute(f"CREATE DATABASE {TEST_DB}")
    get_settings.cache_clear()
    migrate(TEST_URL)
    yield


@pytest.fixture(autouse=True)
def clean():
    yield
    with psycopg.connect(TEST_URL, autocommit=True) as conn:
        conn.execute("TRUNCATE users CASCADE")


@pytest.fixture
def client():
    with TestClient(app) as c:
        yield c


def register(client, email="camila@correo.com", password="12345678", name="Camila"):
    r = client.post("/auth/register", json={"name": name, "email": email, "password": password})
    assert r.status_code == 201, r.text
    return r.json()


def auth(tokens) -> dict:
    return {"Authorization": f"Bearer {tokens['accessToken']}"}


@pytest.fixture
def user(client):
    tokens = register(client)
    return auth(tokens)


def now() -> datetime:
    return datetime.now(UTC)


def iso(dt: datetime) -> str:
    return dt.isoformat()


def make_session(routine_id=None, start=None, sets=None, **extra) -> dict:
    start = start or now() - timedelta(hours=1)
    return {
        "id": str(uuid.uuid4()),
        "routineId": routine_id,
        "title": "Empuje" if routine_id else "Entrenamiento libre",
        "startedAt": iso(start),
        "endedAt": iso(start + timedelta(minutes=50)),
        "plannedExercises": 1,
        "sets": sets
        or [
            {
                "exerciseId": "bench-press",
                "setNumber": n,
                "reps": 8,
                "targetReps": 8,
                "weightKg": 60,
                "meanVelocity": 0.46,
                "rangeDegrees": 82.5,
                "completedAt": iso(start + timedelta(minutes=3 * n)),
            }
            for n in (1, 2)
        ],
        **extra,
    }


def make_routine(edited_at=None, name="Empuje", items=None) -> dict:
    return {
        "name": name,
        "editedAt": iso(edited_at or now()),
        "items": items
        if items is not None
        else [{"exerciseId": "bench-press", "sets": 4, "reps": 8, "weightKg": 60, "restSeconds": 120}],
    }
