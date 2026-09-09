from __future__ import annotations

from datetime import UTC, date, datetime, time
from zoneinfo import ZoneInfo

from .config import get_settings


def institution_zone() -> ZoneInfo:
    return ZoneInfo(get_settings().institution_timezone)


def institution_now(now: datetime | None = None) -> datetime:
    current = now or datetime.now(UTC)
    if current.tzinfo is None:
        current = current.replace(tzinfo=UTC)
    return current.astimezone(institution_zone())


def institution_today(now: datetime | None = None) -> date:
    return institution_now(now).date()


def institution_local_to_utc(day: date, local_time: time) -> datetime:
    return datetime.combine(day, local_time, tzinfo=institution_zone()).astimezone(UTC)
