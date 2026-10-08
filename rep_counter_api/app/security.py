import hashlib
import secrets
from datetime import UTC, datetime, timedelta
from uuid import UUID

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError

from app.config import get_settings

_hasher = PasswordHasher()

# Se verifica contra este hash cuando el correo no existe, para que la
# respuesta tarde lo mismo y no delate qué correos están registrados.
_DUMMY_HASH = _hasher.hash("contraseña-que-nadie-usa")


def hash_password(password: str) -> str:
    return _hasher.hash(password)


def verify_password(password_hash: str | None, password: str) -> bool:
    try:
        return _hasher.verify(password_hash or _DUMMY_HASH, password) and bool(password_hash)
    except (VerificationError, InvalidHashError):
        return False


def needs_rehash(password_hash: str) -> bool:
    return _hasher.check_needs_rehash(password_hash)


def create_access_token(user_id: UUID) -> tuple[str, int]:
    """Devuelve el token y sus segundos de vida."""
    settings = get_settings()
    now = datetime.now(UTC)
    ttl = timedelta(minutes=settings.access_token_minutes)
    token = jwt.encode(
        {"sub": str(user_id), "iat": now, "exp": now + ttl, "type": "access"},
        settings.jwt_secret,
        algorithm="HS256",
    )
    return token, int(ttl.total_seconds())


def decode_access_token(token: str) -> UUID | None:
    try:
        claims = jwt.decode(token, get_settings().jwt_secret, algorithms=["HS256"])
    except jwt.PyJWTError:
        return None
    if claims.get("type") != "access":
        return None
    try:
        return UUID(claims["sub"])
    except (KeyError, ValueError):
        return None


def new_opaque_token() -> tuple[str, bytes]:
    """Token aleatorio para el cliente y su hash para la base de datos."""
    token = secrets.token_urlsafe(32)
    return token, hash_opaque_token(token)


def hash_opaque_token(token: str) -> bytes:
    return hashlib.sha256(token.encode()).digest()
