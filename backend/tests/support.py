"""Shared test fixtures: restore the database to the pristine dev seed.

Import ``setUpModule`` and ``tearDownModule`` from here into a test module so every
module starts from (and leaves behind) the seeded state, whatever order modules run in.
"""
from __future__ import annotations

from pathlib import Path

import psycopg

from backend.app.config import get_settings

SEED_PATH = Path(__file__).resolve().parents[1] / "seeds" / "goal02_dev_seed.sql"


def reseed_database() -> None:
    """Truncate every application table, then re-apply the dev seed."""
    settings = get_settings()
    if settings.app_env != "development":
        raise RuntimeError("Refusing to truncate tables: tests may only reset a development database")
    with psycopg.connect(get_settings().database_url, autocommit=False) as conn:
        tables = [
            row[0]
            for row in conn.execute(
                "SELECT quote_ident(tablename) FROM pg_tables WHERE schemaname = 'public'"
            ).fetchall()
        ]
        if tables:
            conn.execute(f"TRUNCATE {', '.join(tables)} RESTART IDENTITY CASCADE")
        conn.execute(SEED_PATH.read_text())
        conn.commit()
    try:
        from backend.app.redis_service import clear_development_state

        clear_development_state()
    except Exception:  # Redis/dev state is optional in tests
        pass


def setUpModule() -> None:  # noqa: N802 - unittest hook name
    reseed_database()


def tearDownModule() -> None:  # noqa: N802
    reseed_database()
