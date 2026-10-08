from typing import Annotated

from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from psycopg import AsyncConnection

from app.db import get_conn
from app.errors import ApiError
from app.security import decode_access_token

Conn = Annotated[AsyncConnection, Depends(get_conn)]

_bearer = HTTPBearer(auto_error=False)


async def current_user(
    conn: Conn,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
) -> dict:
    """Usuario del token de acceso. 401 si falta, venció o la cuenta ya no
    existe; la app responde renovando con el refresh token."""
    user_id = decode_access_token(credentials.credentials) if credentials else None
    if user_id is None:
        raise ApiError(401, "unauthorized", "Inicia sesión de nuevo.",)
    cur = await conn.execute("SELECT * FROM users WHERE id = %s", (user_id,))
    user = await cur.fetchone()
    if user is None:
        raise ApiError(401, "unauthorized", "Inicia sesión de nuevo.")
    return user


CurrentUser = Annotated[dict, Depends(current_user)]
