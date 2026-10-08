"""Aplica las migraciones de db/migrations en orden, una sola vez cada una.

Uso: python -m app.migrate
"""

from pathlib import Path

import psycopg

from app.config import get_settings

MIGRATIONS = Path(__file__).resolve().parent.parent / "db" / "migrations"


def migrate(database_url: str) -> list[str]:
    applied_now: list[str] = []
    with psycopg.connect(database_url, autocommit=True) as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS schema_migrations (
              name       text PRIMARY KEY,
              applied_at timestamptz NOT NULL DEFAULT now()
            )
            """
        )
        # Evita que dos instancias de la API migren a la vez.
        conn.execute("SELECT pg_advisory_lock(727001)")
        try:
            done = {r[0] for r in conn.execute("SELECT name FROM schema_migrations")}
            for path in sorted(MIGRATIONS.glob("*.sql")):
                if path.name in done:
                    continue
                with conn.transaction():
                    conn.execute(path.read_text())
                    conn.execute(
                        "INSERT INTO schema_migrations (name) VALUES (%s)", (path.name,)
                    )
                applied_now.append(path.name)
        finally:
            conn.execute("SELECT pg_advisory_unlock(727001)")
    return applied_now


if __name__ == "__main__":
    names = migrate(get_settings().database_url)
    print("Aplicadas:", ", ".join(names) if names else "ninguna (ya estaba al día)")
