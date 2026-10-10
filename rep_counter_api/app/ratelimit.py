"""Límite de intentos por IP para las rutas de cuenta.

Frena a quien prueba contraseñas o crea cuentas en masa. Vive en memoria:
basta con una sola instancia de la API (como en Railway hoy). Con varias
instancias, cada una cuenta por separado y conviene moverlo a Redis.
"""

import time
from collections import defaultdict, deque

from fastapi import Request

from app.config import get_settings
from app.errors import ApiError

_hits: dict[tuple[str, str], deque[float]] = defaultdict(deque)


def reset() -> None:
    _hits.clear()


def limit(bucket: str, max_hits: int, per_seconds: int):
    """Dependencia de FastAPI: como máximo `max_hits` peticiones cada
    `per_seconds` segundos por IP en este grupo de rutas."""

    def dependency(request: Request) -> None:
        if not get_settings().rate_limit_enabled:
            return
        # Con --proxy-headers, es la IP real del cliente detrás del proxy.
        ip = request.client.host if request.client else "desconocida"
        now = time.monotonic()
        window = _hits[(bucket, ip)]
        while window and window[0] <= now - per_seconds:
            window.popleft()
        if len(window) >= max_hits:
            retry = int(window[0] + per_seconds - now) + 1
            raise ApiError(
                429,
                "rate_limited",
                "Demasiados intentos. Espera un momento y vuelve a intentar.",
                retryAfter=retry,
            )
        window.append(now)
        # Que el diccionario no crezca sin fin con IPs que ya no vuelven.
        if len(_hits) > 50_000:
            for key in [k for k, v in _hits.items() if not v or v[-1] <= now - 3600]:
                del _hits[key]

    return dependency
