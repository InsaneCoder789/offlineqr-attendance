from collections.abc import Iterable
from typing import Any

import psycopg
from psycopg.rows import dict_row

from .config import get_settings

_pool = None


def connect():
    """Pooled connection when DB_POOL_MAX > 0, else a fresh connection. Use as a context manager."""
    global _pool
    settings = get_settings()
    if settings.db_pool_max > 0:
        if _pool is None:
            from psycopg_pool import ConnectionPool

            _pool = ConnectionPool(
                settings.database_url,
                min_size=1,
                max_size=settings.db_pool_max,
                kwargs={"row_factory": dict_row},
                open=True,
            )
        return _pool.connection()
    return psycopg.connect(settings.database_url, row_factory=dict_row)


def fetch_all(query: str, params: Iterable[Any] = ()) -> list[dict[str, Any]]:
    with psycopg.connect(get_settings().database_url, row_factory=dict_row) as conn:
        with conn.cursor() as cur:
            cur.execute(query, tuple(params))
            return list(cur.fetchall())


def fetch_one(query: str, params: Iterable[Any] = ()) -> dict[str, Any] | None:
    rows = fetch_all(query, params)
    return rows[0] if rows else None

