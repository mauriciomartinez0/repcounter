from collections.abc import AsyncIterator

from fastapi import Request
from psycopg import AsyncConnection
from psycopg.rows import dict_row
from psycopg_pool import AsyncConnectionPool


def create_pool(database_url: str) -> AsyncConnectionPool:
    return AsyncConnectionPool(
        database_url,
        min_size=1,
        max_size=10,
        kwargs={"row_factory": dict_row},
        open=False,
    )


async def get_conn(request: Request) -> AsyncIterator[AsyncConnection]:
    """Una conexión y una transacción por petición: si el endpoint falla, se
    deshace todo lo que escribió."""
    pool: AsyncConnectionPool = request.app.state.pool
    async with pool.connection() as conn:
        yield conn
