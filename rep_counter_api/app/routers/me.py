from fastapi import APIRouter, status

from app.deps import Conn, CurrentUser
from app.errors import ApiError
from app.routers.auth import user_out
from app.schemas import ChangePasswordIn, DeleteMeIn, ExerciseSummary, UpdateMeIn, User
from app.security import hash_password, verify_password

router = APIRouter(prefix="/me", tags=["cuenta"])


@router.get("")
async def get_me(user: CurrentUser) -> User:
    return user_out(user)


@router.patch("")
async def update_me(body: UpdateMeIn, user: CurrentUser, conn: Conn) -> User:
    cur = await conn.execute(
        "UPDATE users SET name = %s WHERE id = %s RETURNING *", (body.name, user["id"])
    )
    return user_out(await cur.fetchone())


@router.put("/password", status_code=status.HTTP_204_NO_CONTENT)
async def change_password(body: ChangePasswordIn, user: CurrentUser, conn: Conn) -> None:
    if user["password_hash"] is not None and not verify_password(
        user["password_hash"], body.current_password or ""
    ):
        raise ApiError(403, "wrong_password", "La contraseña actual no es correcta.")
    await conn.execute(
        "UPDATE users SET password_hash = %s WHERE id = %s",
        (hash_password(body.new_password), user["id"]),
    )


@router.delete("", status_code=status.HTTP_204_NO_CONTENT)
async def delete_me(body: DeleteMeIn, user: CurrentUser, conn: Conn) -> None:
    """Borra la cuenta y todos sus datos (rutinas, sesiones, favoritos)."""
    if user["password_hash"] is not None and not verify_password(
        user["password_hash"], body.password or ""
    ):
        raise ApiError(403, "wrong_password", "La contraseña no es correcta.")
    await conn.execute("DELETE FROM users WHERE id = %s", (user["id"],))


@router.get("/exercise-summary")
async def exercise_summary(user: CurrentUser, conn: Conn) -> list[ExerciseSummary]:
    """Por ejercicio: cuándo se hizo por última vez y con qué peso. Alimenta
    "Recientes" y "Peso · última vez" sin descargar todo el historial."""
    cur = await conn.execute(
        """
        SELECT DISTINCT ON (r.exercise_id)
               r.exercise_id,
               s.started_at AS last_done_at,
               (SELECT r2.weight_kg
                  FROM set_records r2
                  JOIN workout_sessions s2 ON s2.id = r2.session_id
                 WHERE s2.user_id = s.user_id
                   AND r2.exercise_id = r.exercise_id
                   AND r2.weight_kg IS NOT NULL
                 ORDER BY s2.started_at DESC, r2.position DESC
                 LIMIT 1) AS last_weight_kg
          FROM set_records r
          JOIN workout_sessions s ON s.id = r.session_id
         WHERE s.user_id = %s
         ORDER BY r.exercise_id, s.started_at DESC
        """,
        (user["id"],),
    )
    rows = await cur.fetchall()
    rows.sort(key=lambda r: r["last_done_at"], reverse=True)
    return [ExerciseSummary(**r) for r in rows]
