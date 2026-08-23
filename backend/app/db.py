from collections.abc import Iterable
from typing import Any

import psycopg
from psycopg.rows import dict_row

from .config import get_settings


def fetch_all(query: str, params: Iterable[Any] = ()) -> list[dict[str, Any]]:
    with psycopg.connect(get_settings().database_url, row_factory=dict_row) as conn:
        with conn.cursor() as cur:
            cur.execute(query, tuple(params))
            return list(cur.fetchall())


def fetch_one(query: str, params: Iterable[Any] = ()) -> dict[str, Any] | None:
    rows = fetch_all(query, params)
    return rows[0] if rows else None

