"""Sesiones de entrenamiento.

El teléfono guarda cada sesión terminada en una cola local y la sube cuando
hay internet. Como la red puede caerse después de que el servidor guardó pero
antes de que llegue la respuesta, el teléfono va a reintentar sesiones que ya
están guardadas. Por eso:

- El id lo genera el teléfono al empezar el entrenamiento.
- Subir un id que ya existe no vuelve a guardar nada: responde "duplicate"
  con la versión guardada, y el teléfono la saca de la cola igual que con
  "created".
- Las sesiones no se editan después de subidas, así que no hay conflictos.
"""

import base64
from datetime import UTC, datetime, timedelta
from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Query, Response, status
from psycopg import AsyncConnection, errors
from pydantic import ValidationError

from app.config import get_settings
from app.deps import Conn, CurrentUser
from app.errors import ApiError
from app.routers.routines import check_exercises
from app.schemas import (
    Session,
    SessionBatchIn,
    SessionBatchItem,
    SessionBatchResult,
    SessionChanges,
    SessionIn,
    SessionPage,
    SessionUploadResult,
    SetRecord,
)

router = APIRouter(prefix="/sessions", tags=["sesiones"])

MAX_CLOCK_SKEW = timedelta(hours=24)
SYNC_PAGE = 200

_SELECT = """
SELECT s.*,
       COALESCE(t.volume_kg, 0)::float AS volume_kg,
       COALESCE(
         (SELECT json_agg(json_build_object(
                   'exerciseId', r.exercise_id, 'setNumber', r.set_number,
                   'reps', r.reps, 'targetReps', r.target_reps,
                   'weightKg', r.weight_kg, 'meanVelocity', r.mean_velocity,
                   'rangeDegrees', r.range_degrees, 'completedAt', r.completed_at)
                   ORDER BY r.position)
            FROM set_records r WHERE r.session_id = s.id),
         '[]') AS sets
  FROM workout_sessions s
  LEFT JOIN session_totals t ON t.session_id = s.id
"""


def _session(row: dict) -> Session:
    return Session(
        id=row["id"],
        routine_id=row["routine_id"],
        title=row["title"],
        started_at=row["started_at"],
        ended_at=row["ended_at"],
        planned_exercises=row["planned_exercises"],
        received_at=row["received_at"],
        volume_kg=row["volume_kg"],
        sets=[SetRecord.model_validate(s) for s in row["sets"]],
    )


async def _load_one(conn: AsyncConnection, session_id: UUID) -> Session:
    cur = await conn.execute(_SELECT + " WHERE s.id = %s", (session_id,))
    return _session(await cur.fetchone())


async def _existing_owner(conn: AsyncConnection, session_id: UUID) -> UUID | None:
    cur = await conn.execute("SELECT user_id FROM workout_sessions WHERE id = %s", (session_id,))
    row = await cur.fetchone()
    return row["user_id"] if row else None


async def store_session(
    conn: AsyncConnection, user_id: UUID, body: SessionIn
) -> tuple[Literal["created", "duplicate"], Session]:
    # Primero, ¿es un reintento? Así un reintento siempre se acepta aunque
    # algo de lo que referencia haya cambiado desde la primera subida.
    owner = await _existing_owner(conn, body.id)
    if owner is not None:
        if owner != user_id:
            raise ApiError(409, "id_conflict", "Ese id ya está en uso. Genera otro.")
        return "duplicate", await _load_one(conn, body.id)

    if body.started_at > datetime.now(UTC) + MAX_CLOCK_SKEW:
        raise ApiError(422, "clock_skew", "La hora del teléfono no es correcta.")
    await check_exercises(conn, {s.exercise_id for s in body.sets})
    if body.routine_id is not None:
        # Las rutinas borradas siguen en la base como "lápida", así que una
        # sesión con una rutina borrada después también entra.
        cur = await conn.execute(
            "SELECT 1 FROM routines WHERE id = %s AND user_id = %s",
            (body.routine_id, user_id),
        )
        if await cur.fetchone() is None:
            raise ApiError(
                422,
                "unknown_routine",
                "La rutina de esta sesión no está en el servidor. Sube las "
                "rutinas antes que las sesiones.",
            )

    cur = await conn.execute(
        """
        INSERT INTO workout_sessions
          (id, user_id, routine_id, title, started_at, ended_at, planned_exercises)
        VALUES (%s, %s, %s, %s, %s, %s, %s)
        ON CONFLICT (id) DO NOTHING
        RETURNING id
        """,
        (
            body.id, user_id, body.routine_id, body.title,
            body.started_at, body.ended_at, body.planned_exercises,
        ),
    )
    if await cur.fetchone() is None:
        # Otra petición con la misma sesión ganó la carrera hace un instante.
        if await _existing_owner(conn, body.id) != user_id:
            raise ApiError(409, "id_conflict", "Ese id ya está en uso. Genera otro.")
        return "duplicate", await _load_one(conn, body.id)

    async with conn.cursor() as c:
        await c.executemany(
            """
            INSERT INTO set_records
              (session_id, position, exercise_id, set_number, reps, target_reps,
               weight_kg, mean_velocity, range_degrees, completed_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """,
            [
                (
                    body.id, pos, s.exercise_id, s.set_number, s.reps, s.target_reps,
                    s.weight_kg, s.mean_velocity, s.range_degrees, s.completed_at,
                )
                for pos, s in enumerate(body.sets, start=1)
            ],
        )
    return "created", await _load_one(conn, body.id)


@router.post("", responses={200: {"description": "Ya existía (reintento)"}})
async def upload_session(
    body: SessionIn, user: CurrentUser, conn: Conn, response: Response
) -> SessionUploadResult:
    """201 si se guardó ahora, 200 si ya estaba guardada (reintento)."""
    result, session = await store_session(conn, user["id"], body)
    response.status_code = status.HTTP_201_CREATED if result == "created" else status.HTTP_200_OK
    return SessionUploadResult(status=result, session=session)


@router.post("/batch")
async def upload_batch(body: SessionBatchIn, user: CurrentUser, conn: Conn) -> SessionBatchResult:
    """Sube la cola completa de una vez. Cada sesión se guarda o se rechaza
    por separado; el teléfono saca de la cola las "created", "duplicate" y
    "rejected" (estas últimas avisando al usuario)."""
    limit = get_settings().max_batch_sessions
    if len(body.sessions) > limit:
        raise ApiError(413, "batch_too_large", f"Máximo {limit} sesiones por envío.")

    results: list[SessionBatchItem] = []
    for raw in body.sessions:
        try:
            session = SessionIn.model_validate(raw)
        except ValidationError as exc:
            try:
                raw_id = UUID(str(raw.get("id")))
            except ValueError:
                raise ApiError(
                    422, "validation_error", "Una sesión del lote no tiene un id válido."
                ) from None
            results.append(SessionBatchItem(
                id=raw_id,
                status="rejected",
                error={"code": "validation_error", "message": str(exc.errors()[0]["msg"])},
            ))
            continue
        try:
            # Punto de guardado: si esta sesión falla, solo se deshace ella.
            async with conn.transaction():
                result, _ = await store_session(conn, user["id"], session)
            results.append(SessionBatchItem(id=session.id, status=result))
        except ApiError as exc:
            results.append(SessionBatchItem(
                id=session.id, status="rejected", error={"code": exc.code, "message": exc.message}
            ))
        except errors.IntegrityError:
            results.append(SessionBatchItem(
                id=session.id,
                status="rejected",
                error={"code": "invalid_session", "message": "La sesión tiene datos inválidos."},
            ))
    return SessionBatchResult(results=results)


def _encode_cursor(started_at: datetime, session_id: UUID) -> str:
    raw = f"{started_at.isoformat()}|{session_id}"
    return base64.urlsafe_b64encode(raw.encode()).decode()


def _decode_cursor(cursor: str) -> tuple[datetime, UUID]:
    try:
        started, sid = base64.urlsafe_b64decode(cursor.encode()).decode().split("|")
        return datetime.fromisoformat(started), UUID(sid)
    except ValueError:
        raise ApiError(400, "invalid_cursor", "El cursor no es válido.") from None


@router.get("")
async def list_sessions(
    user: CurrentUser,
    conn: Conn,
    cursor: str | None = None,
    limit: int = Query(default=20, ge=1, le=100),
) -> SessionPage:
    """Historial, de la más reciente a la más antigua, por páginas."""
    if cursor is None:
        where, params = "s.user_id = %s", (user["id"],)
    else:
        started, sid = _decode_cursor(cursor)
        where = "s.user_id = %s AND (s.started_at, s.id) < (%s, %s)"
        params = (user["id"], started, sid)
    cur = await conn.execute(
        _SELECT + f" WHERE {where} ORDER BY s.started_at DESC, s.id DESC LIMIT %s",
        (*params, limit + 1),
    )
    rows = await cur.fetchall()
    page = rows[:limit]
    next_cursor = (
        _encode_cursor(page[-1]["started_at"], page[-1]["id"]) if len(rows) > limit else None
    )
    return SessionPage(sessions=[_session(r) for r in page], next_cursor=next_cursor)


@router.get("/sync")
async def sync_sessions(user: CurrentUser, conn: Conn, since: datetime) -> SessionChanges:
    """Sesiones que llegaron al servidor desde `since`, por ejemplo las que
    subió otro teléfono. Puede repetir alguna ya recibida; como el id es el
    mismo, el teléfono simplemente la reemplaza."""
    cur = await conn.execute("SELECT clock_timestamp() - interval '1 minute' AS t")
    server_time = (await cur.fetchone())["t"]
    cur = await conn.execute(
        _SELECT + " WHERE s.user_id = %s AND s.received_at >= %s ORDER BY s.received_at LIMIT %s",
        (user["id"], since, SYNC_PAGE),
    )
    rows = await cur.fetchall()
    has_more = len(rows) == SYNC_PAGE
    if has_more:
        server_time = rows[-1]["received_at"]
    return SessionChanges(
        sessions=[_session(r) for r in rows], server_time=server_time, has_more=has_more
    )


@router.get("/{session_id}")
async def get_session(session_id: UUID, user: CurrentUser, conn: Conn) -> Session:
    cur = await conn.execute(
        _SELECT + " WHERE s.id = %s AND s.user_id = %s", (session_id, user["id"])
    )
    row = await cur.fetchone()
    if row is None:
        raise ApiError(404, "session_not_found", "Esa sesión no existe.")
    return _session(row)
