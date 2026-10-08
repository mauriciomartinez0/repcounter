from contextlib import asynccontextmanager

from fastapi import FastAPI

from app import errors
from app.config import get_settings
from app.db import create_pool
from app.routers import auth, exercises, me, routines, sessions


@asynccontextmanager
async def lifespan(app: FastAPI):
    pool = create_pool(get_settings().database_url)
    await pool.open()
    app.state.pool = pool
    try:
        yield
    finally:
        await pool.close()


app = FastAPI(
    title="Rep Counter API",
    version="1.0.0",
    description=(
        "Cuentas, catálogo de ejercicios, rutinas e historial del contador de "
        "repeticiones. Pensada para uso sin conexión: los ids de rutinas y "
        "sesiones los genera el teléfono y los reintentos no duplican nada."
    ),
    lifespan=lifespan,
)
errors.install(app)

for module in (auth, me, exercises, routines, sessions):
    app.include_router(module.router)


@app.get("/health", tags=["sistema"])
async def health() -> dict:
    async with app.state.pool.connection() as conn:
        await conn.execute("SELECT 1")
    return {"status": "ok"}
