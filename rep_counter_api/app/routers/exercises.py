from datetime import UTC, datetime, timedelta

from fastapi import APIRouter, Header, Response, status

from app.deps import Conn, CurrentUser
from app.errors import ApiError
from app.schemas import (
    Catalog,
    Exercise,
    Metric,
    Progress,
    ProgressPoint,
    ProgressRange,
)

router = APIRouter(tags=["catálogo"])

_EXERCISE_SQL = """
SELECT e.*,
       COALESCE(array_agg(t.body ORDER BY t.position)
                FILTER (WHERE t.body IS NOT NULL), '{}') AS tutorial_steps
  FROM exercises e
  LEFT JOIN tutorial_steps t ON t.exercise_id = e.id
"""


async def _exercise_exists(conn: Conn, exercise_id: str) -> None:
    cur = await conn.execute("SELECT 1 FROM exercises WHERE id = %s", (exercise_id,))
    if await cur.fetchone() is None:
        raise ApiError(404, "unknown_exercise", "Ese ejercicio no existe.")


@router.get("/exercises", response_model=Catalog)
async def catalog(
    conn: Conn,
    response: Response,
    if_none_match: str | None = Header(default=None),
):
    """Catálogo completo. Público: la app puede actualizarlo antes de iniciar
    sesión. Manda `If-None-Match` con la versión que tienes; si no cambió, la
    respuesta es 304 sin cuerpo."""
    cur = await conn.execute("SELECT etag FROM catalog_version")
    etag = f'"{(await cur.fetchone())["etag"]}"'
    headers = {"ETag": etag, "Cache-Control": "no-cache"}
    if if_none_match and etag in [t.strip() for t in if_none_match.split(",")]:
        return Response(status_code=status.HTTP_304_NOT_MODIFIED, headers=headers)
    cur = await conn.execute(_EXERCISE_SQL + " GROUP BY e.id ORDER BY e.muscle_group, e.name")
    rows = await cur.fetchall()
    response.headers.update(headers)
    return Catalog(version=etag.strip('"'), exercises=[Exercise(**r) for r in rows])


@router.get("/exercises/{exercise_id}")
async def get_exercise(exercise_id: str, conn: Conn) -> Exercise:
    cur = await conn.execute(_EXERCISE_SQL + " WHERE e.id = %s GROUP BY e.id", (exercise_id,))
    row = await cur.fetchone()
    if row is None:
        raise ApiError(404, "unknown_exercise", "Ese ejercicio no existe.")
    return Exercise(**row)


# --- Favoritos ----------------------------------------------------------------


@router.get("/favorites", tags=["favoritos"])
async def list_favorites(user: CurrentUser, conn: Conn) -> list[str]:
    cur = await conn.execute(
        "SELECT exercise_id FROM favorites WHERE user_id = %s ORDER BY created_at",
        (user["id"],),
    )
    return [r["exercise_id"] for r in await cur.fetchall()]


@router.put("/favorites/{exercise_id}", status_code=status.HTTP_204_NO_CONTENT, tags=["favoritos"])
async def add_favorite(exercise_id: str, user: CurrentUser, conn: Conn) -> None:
    """Idempotente: marcarlo dos veces deja un solo favorito."""
    await _exercise_exists(conn, exercise_id)
    await conn.execute(
        "INSERT INTO favorites (user_id, exercise_id) VALUES (%s, %s) ON CONFLICT DO NOTHING",
        (user["id"], exercise_id),
    )


@router.delete("/favorites/{exercise_id}", status_code=status.HTTP_204_NO_CONTENT, tags=["favoritos"])
async def remove_favorite(exercise_id: str, user: CurrentUser, conn: Conn) -> None:
    await conn.execute(
        "DELETE FROM favorites WHERE user_id = %s AND exercise_id = %s",
        (user["id"], exercise_id),
    )


# --- Progreso -----------------------------------------------------------------

# Un valor por sesión, igual que la pantalla de Progreso.
_METRIC_SQL = {
    Metric.weight: "max(r.weight_kg)",
    Metric.reps: "sum(r.reps)",
    Metric.volume: "NULLIF(sum(r.reps * COALESCE(r.weight_kg, 0)), 0)",
    # Epley: peso × (1 + reps / 30).
    Metric.one_rep_max: "max(r.weight_kg * (1 + r.reps / 30.0))",
    Metric.velocity: "avg(r.mean_velocity)",
    Metric.range: "max(r.range_degrees)",
}

_RANGE_DAYS = {ProgressRange.weeks4: 28, ProgressRange.weeks12: 84, ProgressRange.all: None}


@router.get("/exercises/{exercise_id}/progress", tags=["progreso"])
async def progress(
    exercise_id: str,
    user: CurrentUser,
    conn: Conn,
    metric: Metric = Metric.weight,
    range: ProgressRange = ProgressRange.weeks12,
) -> Progress:
    await _exercise_exists(conn, exercise_id)
    days = _RANGE_DAYS[range]
    since = datetime.now(UTC) - timedelta(days=days) if days else None
    cur = await conn.execute(
        f"""
        SELECT s.started_at AS date, {_METRIC_SQL[metric]}::float AS value
          FROM set_records r
          JOIN workout_sessions s ON s.id = r.session_id
         WHERE s.user_id = %(user)s
           AND r.exercise_id = %(exercise)s
           AND (%(since)s::timestamptz IS NULL OR s.started_at >= %(since)s)
         GROUP BY s.id, s.started_at
        HAVING {_METRIC_SQL[metric]} IS NOT NULL
         ORDER BY s.started_at
        """,
        {"user": user["id"], "exercise": exercise_id, "since": since},
    )
    points = [ProgressPoint(**r) for r in await cur.fetchall()]
    return Progress(
        exercise_id=exercise_id,
        metric=metric,
        range=range,
        points=points,
        latest=points[-1] if points else None,
        # Ante empate, la más reciente.
        best=max(reversed(points), key=lambda p: p.value) if points else None,
        average=sum(p.value for p in points) / len(points) if points else None,
        change=points[-1].value - points[0].value if len(points) > 1 else None,
    )
