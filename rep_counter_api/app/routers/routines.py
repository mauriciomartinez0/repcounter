"""Rutinas con sincronización para uso sin conexión.

- El teléfono crea el UUID y escribe con PUT /routines/{id}: crear y editar
  son la misma operación, y repetirla da el mismo resultado.
- Si dos teléfonos editaron sin conexión, gana la edición más reciente según
  `editedAt` (la hora del teléfono al editar).
- Borrar deja una "lápida": GET /routines?since=... la devuelve con
  `deletedAt` para que los demás teléfonos también la quiten.
"""

from datetime import UTC, datetime, timedelta
from uuid import UUID

from fastapi import APIRouter, status
from psycopg import AsyncConnection

from app.deps import Conn, CurrentUser
from app.errors import ApiError
from app.schemas import Routine, RoutineChanges, RoutineIn, RoutineItem, RoutineWriteResult

router = APIRouter(prefix="/routines", tags=["rutinas"])

# Margen para no perder cambios de transacciones que terminaron justo
# mientras se leía; repetir algunos en la siguiente sincronización no hace daño.
SYNC_OVERLAP = timedelta(minutes=1)

# Un teléfono con la hora muy adelantada ganaría todas las ediciones.
MAX_CLOCK_SKEW = timedelta(hours=24)


async def _load(conn: AsyncConnection, where: str, params: tuple) -> list[Routine]:
    cur = await conn.execute(
        f"""
        SELECT r.*,
               COALESCE(
                 json_agg(json_build_object(
                   'exerciseId', i.exercise_id, 'sets', i.sets, 'reps', i.reps,
                   'weightKg', i.weight_kg, 'restSeconds', i.rest_seconds)
                   ORDER BY i.position) FILTER (WHERE i.routine_id IS NOT NULL),
                 '[]') AS items
          FROM routines r
          LEFT JOIN routine_items i ON i.routine_id = r.id
         WHERE {where}
         GROUP BY r.id
         ORDER BY r.created_at
        """,
        params,
    )
    return [
        Routine(
            id=r["id"],
            name=r["name"],
            items=[RoutineItem.model_validate(i) for i in r["items"]],
            created_at=r["created_at"],
            edited_at=r["edited_at"],
            updated_at=r["updated_at"],
            deleted_at=r["deleted_at"],
        )
        for r in await cur.fetchall()
    ]


async def check_exercises(conn: AsyncConnection, ids: set[str]) -> None:
    if not ids:
        return
    cur = await conn.execute("SELECT id FROM exercises WHERE id = ANY(%s)", (list(ids),))
    missing = ids - {r["id"] for r in await cur.fetchall()}
    if missing:
        raise ApiError(
            422, "unknown_exercise", "Hay ejercicios que no existen.", exerciseIds=sorted(missing)
        )


@router.get("")
async def list_routines(
    user: CurrentUser, conn: Conn, since: datetime | None = None
) -> RoutineChanges:
    """Sin `since`: todas las rutinas vigentes. Con `since` (el `serverTime`
    de la sincronización anterior): solo las que cambiaron, borradas incluidas."""
    cur = await conn.execute("SELECT clock_timestamp() AS now")
    server_time = (await cur.fetchone())["now"] - SYNC_OVERLAP
    if since is None:
        routines = await _load(conn, "r.user_id = %s AND r.deleted_at IS NULL", (user["id"],))
    else:
        routines = await _load(conn, "r.user_id = %s AND r.updated_at > %s", (user["id"], since))
    return RoutineChanges(routines=routines, server_time=server_time)


@router.get("/{routine_id}")
async def get_routine(routine_id: UUID, user: CurrentUser, conn: Conn) -> Routine:
    found = await _load(conn, "r.id = %s AND r.user_id = %s", (routine_id, user["id"]))
    if not found:
        raise ApiError(404, "routine_not_found", "Esa rutina no existe.")
    return found[0]


@router.put("/{routine_id}")
async def put_routine(
    routine_id: UUID, body: RoutineIn, user: CurrentUser, conn: Conn
) -> RoutineWriteResult:
    if body.edited_at > datetime.now(UTC) + MAX_CLOCK_SKEW:
        raise ApiError(422, "clock_skew", "La hora del teléfono no es correcta.")
    await check_exercises(conn, {i.exercise_id for i in body.items})

    cur = await conn.execute(
        "SELECT user_id, edited_at, deleted_at FROM routines WHERE id = %s FOR UPDATE",
        (routine_id,),
    )
    existing = await cur.fetchone()
    if existing is not None:
        if existing["user_id"] != user["id"]:
            # Un UUID repetido entre usuarios no debería pasar nunca; no se
            # dice de quién es.
            raise ApiError(409, "id_conflict", "Ese id ya está en uso. Genera otro.")
        if existing["deleted_at"] is not None:
            raise ApiError(410, "routine_deleted", "Esa rutina se borró en otro dispositivo.")
        if existing["edited_at"] > body.edited_at:
            # El servidor tiene una edición posterior: gana esa.
            current = await _load(conn, "r.id = %s", (routine_id,))
            return RoutineWriteResult(routine=current[0], applied=False)
        await conn.execute(
            "UPDATE routines SET name = %s, edited_at = %s WHERE id = %s",
            (body.name, body.edited_at, routine_id),
        )
        await conn.execute("DELETE FROM routine_items WHERE routine_id = %s", (routine_id,))
    else:
        await conn.execute(
            "INSERT INTO routines (id, user_id, name, edited_at) VALUES (%s, %s, %s, %s)",
            (routine_id, user["id"], body.name, body.edited_at),
        )

    if body.items:
        async with conn.cursor() as cur:
            await cur.executemany(
                """
                INSERT INTO routine_items
                  (routine_id, position, exercise_id, sets, reps, weight_kg, rest_seconds)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                """,
                [
                    (routine_id, pos, i.exercise_id, i.sets, i.reps, i.weight_kg, i.rest_seconds)
                    for pos, i in enumerate(body.items, start=1)
                ],
            )
    saved = await _load(conn, "r.id = %s", (routine_id,))
    return RoutineWriteResult(routine=saved[0], applied=True)


@router.delete("/{routine_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_routine(routine_id: UUID, user: CurrentUser, conn: Conn) -> None:
    """Idempotente. Si la rutina nunca llegó al servidor (se creó y borró sin
    conexión), también responde 204. Las sesiones hechas con ella se
    conservan."""
    await conn.execute(
        """
        UPDATE routines SET deleted_at = now()
         WHERE id = %s AND user_id = %s AND deleted_at IS NULL
        """,
        (routine_id, user["id"]),
    )
    await conn.execute(
        """
        DELETE FROM routine_items i USING routines r
         WHERE i.routine_id = r.id AND r.id = %s AND r.user_id = %s
        """,
        (routine_id, user["id"]),
    )
