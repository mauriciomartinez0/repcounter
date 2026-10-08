from datetime import UTC, datetime
from uuid import UUID

from fastapi import APIRouter, status
from fastapi.concurrency import run_in_threadpool
from psycopg import AsyncConnection, errors

from app import mailer
from app.config import get_settings
from app.deps import Conn, CurrentUser
from app.errors import ApiError
from app.schemas import (
    AuthResponse,
    ForgotPasswordIn,
    GoogleIn,
    LoginIn,
    RefreshIn,
    RegisterIn,
    ResetPasswordIn,
    User,
)
from app.security import (
    create_access_token,
    hash_opaque_token,
    hash_password,
    needs_rehash,
    new_opaque_token,
    verify_password,
)

router = APIRouter(prefix="/auth", tags=["cuenta"])


def user_out(row: dict) -> User:
    return User(
        id=row["id"],
        name=row["name"],
        email=row["email"],
        has_password=row["password_hash"] is not None,
        has_google=row["google_sub"] is not None,
        created_at=row["created_at"],
    )


async def issue_tokens(conn: AsyncConnection, user: dict, replaces: UUID | None = None) -> AuthResponse:
    access, expires_in = create_access_token(user["id"])
    refresh, refresh_hash = new_opaque_token()
    days = get_settings().refresh_token_days
    cur = await conn.execute(
        """
        INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
        VALUES (%s, %s, now() + make_interval(days => %s))
        RETURNING id
        """,
        (user["id"], refresh_hash, days),
    )
    new_id = (await cur.fetchone())["id"]
    if replaces is not None:
        await conn.execute(
            "UPDATE refresh_tokens SET revoked_at = now(), replaced_by = %s WHERE id = %s",
            (new_id, replaces),
        )
    return AuthResponse(
        user=user_out(user), access_token=access, refresh_token=refresh, expires_in=expires_in
    )


@router.post("/register", status_code=status.HTTP_201_CREATED)
async def register(body: RegisterIn, conn: Conn) -> AuthResponse:
    try:
        cur = await conn.execute(
            "INSERT INTO users (name, email, password_hash) VALUES (%s, %s, %s) RETURNING *",
            (body.name, body.email, hash_password(body.password)),
        )
    except errors.UniqueViolation:
        raise ApiError(409, "email_taken", "Ya existe una cuenta con ese correo.") from None
    return await issue_tokens(conn, await cur.fetchone())


@router.post("/login")
async def login(body: LoginIn, conn: Conn) -> AuthResponse:
    cur = await conn.execute("SELECT * FROM users WHERE email = %s", (body.email,))
    user = await cur.fetchone()
    if not verify_password(user["password_hash"] if user else None, body.password):
        raise ApiError(401, "invalid_credentials", "Correo o contraseña incorrectos.")
    if needs_rehash(user["password_hash"]):
        await conn.execute(
            "UPDATE users SET password_hash = %s WHERE id = %s",
            (hash_password(body.password), user["id"]),
        )
    return await issue_tokens(conn, user)


def _verify_google_token(token: str, audiences: list[str]) -> dict:
    # Importado aquí: solo hace falta si Google está configurado.
    from google.auth.transport import requests as google_requests
    from google.oauth2 import id_token

    claims = id_token.verify_oauth2_token(token, google_requests.Request())
    if claims.get("aud") not in audiences:
        raise ValueError("audiencia inesperada")
    return claims


@router.post("/google")
async def google(body: GoogleIn, conn: Conn) -> AuthResponse:
    """Recibe el ID token que entrega Google Sign-In en el teléfono."""
    audiences = get_settings().google_audiences
    if not audiences:
        raise ApiError(503, "google_disabled", "El acceso con Google no está configurado.")
    try:
        claims = await run_in_threadpool(_verify_google_token, body.id_token, audiences)
    except ValueError:
        raise ApiError(401, "invalid_google_token", "No se pudo verificar la cuenta de Google.") from None
    if not claims.get("email_verified"):
        raise ApiError(401, "invalid_google_token", "Google no confirmó ese correo.")

    sub, email = claims["sub"], claims["email"]
    name = (claims.get("name") or email.split("@")[0])[:100]

    cur = await conn.execute("SELECT * FROM users WHERE google_sub = %s", (sub,))
    user = await cur.fetchone()
    if user is None:
        # Mismo correo ya registrado con contraseña: Google confirmó que es
        # suyo, así que se vincula a esa cuenta en vez de crear otra.
        cur = await conn.execute(
            """
            INSERT INTO users (name, email, google_sub) VALUES (%s, %s, %s)
            ON CONFLICT (email) DO UPDATE SET google_sub = EXCLUDED.google_sub
            RETURNING *
            """,
            (name, email, sub),
        )
        user = await cur.fetchone()
    return await issue_tokens(conn, user)


@router.post("/refresh")
async def refresh(body: RefreshIn, conn: Conn) -> AuthResponse:
    """Cambia un refresh token por uno nuevo más un access token. Cada
    refresh token sirve una sola vez."""
    cur = await conn.execute(
        "SELECT * FROM refresh_tokens WHERE token_hash = %s FOR UPDATE",
        (hash_opaque_token(body.refresh_token),),
    )
    token = await cur.fetchone()
    if token is None or token["expires_at"] <= datetime.now(UTC):
        raise ApiError(401, "invalid_refresh_token", "Inicia sesión de nuevo.")
    if token["revoked_at"] is not None:
        # Un token ya usado volvió a aparecer: alguien más lo tiene. Se
        # cierran todas las sesiones de la cuenta. Este cambio debe quedar
        # guardado aunque la petición termine en error.
        await conn.execute(
            "UPDATE refresh_tokens SET revoked_at = now() WHERE user_id = %s AND revoked_at IS NULL",
            (token["user_id"],),
        )
        await conn.commit()
        raise ApiError(401, "refresh_token_reused", "Inicia sesión de nuevo.")
    cur = await conn.execute("SELECT * FROM users WHERE id = %s", (token["user_id"],))
    return await issue_tokens(conn, await cur.fetchone(), replaces=token["id"])


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(body: RefreshIn, conn: Conn) -> None:
    await conn.execute(
        "UPDATE refresh_tokens SET revoked_at = now() WHERE token_hash = %s AND revoked_at IS NULL",
        (hash_opaque_token(body.refresh_token),),
    )


@router.post("/logout-all", status_code=status.HTTP_204_NO_CONTENT)
async def logout_all(user: CurrentUser, conn: Conn) -> None:
    """Cierra la sesión en todos los teléfonos."""
    await conn.execute(
        "UPDATE refresh_tokens SET revoked_at = now() WHERE user_id = %s AND revoked_at IS NULL",
        (user["id"],),
    )


@router.post("/forgot-password", status_code=status.HTTP_202_ACCEPTED)
async def forgot_password(body: ForgotPasswordIn, conn: Conn) -> dict:
    """Siempre responde lo mismo, exista o no el correo."""
    cur = await conn.execute("SELECT * FROM users WHERE email = %s", (body.email,))
    user = await cur.fetchone()
    if user is not None:
        token, token_hash = new_opaque_token()
        minutes = get_settings().password_reset_minutes
        await conn.execute(
            """
            INSERT INTO password_reset_tokens (token_hash, user_id, expires_at)
            VALUES (%s, %s, now() + make_interval(mins => %s))
            """,
            (token_hash, user["id"], minutes),
        )
        mailer.send_password_reset(user["email"], user["name"], token)
    return {"message": "Si el correo está registrado, te enviamos un código."}


@router.post("/reset-password", status_code=status.HTTP_204_NO_CONTENT)
async def reset_password(body: ResetPasswordIn, conn: Conn) -> None:
    cur = await conn.execute(
        """
        UPDATE password_reset_tokens SET used_at = now()
         WHERE token_hash = %s AND used_at IS NULL AND expires_at > now()
        RETURNING user_id
        """,
        (hash_opaque_token(body.token),),
    )
    row = await cur.fetchone()
    if row is None:
        raise ApiError(400, "invalid_reset_token", "El código no es válido o ya venció.")
    await conn.execute(
        "UPDATE users SET password_hash = %s WHERE id = %s",
        (hash_password(body.new_password), row["user_id"]),
    )
    # Con la contraseña nueva, nadie más debe seguir dentro.
    await conn.execute(
        "UPDATE refresh_tokens SET revoked_at = now() WHERE user_id = %s AND revoked_at IS NULL",
        (row["user_id"],),
    )

