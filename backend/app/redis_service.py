from __future__ import annotations

from dataclasses import dataclass
from hashlib import sha256
import json
import secrets
from threading import Lock
from time import time
from typing import Any
from uuid import UUID

from redis import Redis
from redis.exceptions import RedisError

from .config import get_settings
from .errors import ApiError


_LOCK = Lock()
_CLIENT: Redis | None = None
_DEV_CACHE: dict[str, tuple[float, str]] = {}


def _client() -> Redis:
    global _CLIENT
    if _CLIENT is None:
        with _LOCK:
            if _CLIENT is None:
                _CLIENT = Redis.from_url(
                    get_settings().redis_url,
                    decode_responses=True,
                    socket_connect_timeout=0.35,
                    socket_timeout=0.35,
                    health_check_interval=30,
                )
    return _CLIENT


def assert_available() -> None:
    try:
        _client().ping()
    except RedisError as exc:
        if get_settings().redis_required:
            raise RuntimeError("Redis coordination is required but unavailable") from exc


def _unavailable() -> None:
    raise ApiError(
        "COORDINATION_UNAVAILABLE",
        "Temporary coordination service is unavailable. Retry shortly.",
        503,
    )


def _hashed(value: str) -> str:
    return sha256(value.encode("utf-8")).hexdigest()


def _dev_get(key: str) -> str | None:
    item = _DEV_CACHE.get(key)
    if item is None or item[0] <= time():
        _DEV_CACHE.pop(key, None)
        return None
    return item[1]


def _dev_set(key: str, value: str, ttl_seconds: int) -> None:
    _DEV_CACHE[key] = (time() + ttl_seconds, value)


_RATE_LIMIT_LUA = """
local count = redis.call('INCR', KEYS[1])
if count == 1 then redis.call('EXPIRE', KEYS[1], ARGV[1]) end
local ttl = redis.call('TTL', KEYS[1])
return {count, ttl}
"""


@dataclass(frozen=True)
class RateLimitResult:
    allowed: bool
    retry_after_seconds: int


def consume_rate_limit(scope: str, subject: str, *, limit: int, window_seconds: int) -> RateLimitResult:
    bucket = int(time() // window_seconds)
    key = f"attendance:rate:{scope}:{_hashed(subject)}:{bucket}"
    try:
        count, ttl = _client().eval(_RATE_LIMIT_LUA, 1, key, window_seconds)
        return RateLimitResult(allowed=int(count) <= limit, retry_after_seconds=max(1, int(ttl)))
    except RedisError:
        if get_settings().redis_required:
            _unavailable()
        # Development remains usable without a local Redis process, but this path
        # is deliberately never selected in production.
        counter_key = f"{key}:dev"
        raw = _dev_get(counter_key)
        count = int(raw or "0") + 1
        _dev_set(counter_key, str(count), window_seconds)
        return RateLimitResult(allowed=count <= limit * 10, retry_after_seconds=window_seconds)


def create_faculty_session(faculty_id: UUID) -> tuple[str, str]:
    token = secrets.token_urlsafe(48)
    csrf_token = secrets.token_urlsafe(32)
    settings = get_settings()
    payload = json.dumps({"faculty_id": str(faculty_id), "csrf": csrf_token})
    key = f"attendance:faculty-session:{_hashed(token)}"
    index_key = f"attendance:faculty-session-index:{faculty_id}"
    try:
        pipe = _client().pipeline(transaction=True)
        pipe.set(key, payload, ex=settings.faculty_session_ttl_seconds, nx=True)
        pipe.sadd(index_key, key)
        pipe.expire(index_key, settings.faculty_session_ttl_seconds)
        pipe.execute()
    except RedisError:
        if settings.redis_required:
            _unavailable()
        _dev_set(key, payload, settings.faculty_session_ttl_seconds)
        indexed = json.loads(_dev_get(index_key) or "[]")
        if key not in indexed:
            indexed.append(key)
        _dev_set(index_key, json.dumps(indexed), settings.faculty_session_ttl_seconds)
    return token, csrf_token


def faculty_session(token: str) -> dict[str, str] | None:
    key = f"attendance:faculty-session:{_hashed(token)}"
    try:
        raw = _client().get(key)
    except RedisError:
        if get_settings().redis_required:
            _unavailable()
        raw = _dev_get(key)
    if not raw:
        return None
    try:
        payload = json.loads(raw)
        if not isinstance(payload.get("faculty_id"), str) or not isinstance(payload.get("csrf"), str):
            return None
        return payload
    except (TypeError, ValueError):
        return None


def revoke_faculty_session(token: str) -> None:
    if not token:
        return
    key = f"attendance:faculty-session:{_hashed(token)}"
    try:
        _client().delete(key)
    except RedisError:
        if get_settings().redis_required:
            _unavailable()
        _DEV_CACHE.pop(key, None)


def revoke_faculty_sessions(faculty_id: UUID) -> None:
    """Invalidate every browser session after a faculty credential change."""
    index_key = f"attendance:faculty-session-index:{faculty_id}"
    try:
        keys = list(_client().smembers(index_key))
        pipe = _client().pipeline(transaction=True)
        if keys:
            pipe.delete(*keys)
        pipe.delete(index_key)
        pipe.execute()
    except RedisError:
        if get_settings().redis_required:
            _unavailable()
        keys = json.loads(_dev_get(index_key) or "[]")
        for key in keys:
            _DEV_CACHE.pop(key, None)
        _DEV_CACHE.pop(index_key, None)


def create_student_session(student_id: UUID, *, must_change_password: bool = False) -> str:
    """Issue an opaque mobile session and index it for emergency revocation."""
    token = secrets.token_urlsafe(48)
    settings = get_settings()
    key = f"attendance:student-session:{_hashed(token)}"
    index_key = f"attendance:student-session-index:{student_id}"
    payload = json.dumps({"student_id": str(student_id), "must_change_password": must_change_password})
    try:
        pipe = _client().pipeline(transaction=True)
        pipe.set(key, payload, ex=settings.student_session_ttl_seconds, nx=True)
        pipe.sadd(index_key, key)
        pipe.expire(index_key, settings.student_session_ttl_seconds)
        pipe.execute()
    except RedisError:
        if settings.redis_required:
            _unavailable()
        _dev_set(key, payload, settings.student_session_ttl_seconds)
        indexed = json.loads(_dev_get(index_key) or "[]")
        if key not in indexed:
            indexed.append(key)
        _dev_set(index_key, json.dumps(indexed), settings.student_session_ttl_seconds)
    return token


def student_session(token: str) -> dict[str, str] | None:
    if not token or len(token) > 256:
        return None
    key = f"attendance:student-session:{_hashed(token)}"
    try:
        raw = _client().get(key)
    except RedisError:
        if get_settings().redis_required:
            _unavailable()
        raw = _dev_get(key)
    if not raw:
        return None
    try:
        payload = json.loads(raw)
        return payload if isinstance(payload.get("student_id"), str) else None
    except (TypeError, ValueError):
        return None


def revoke_student_sessions(student_id: UUID) -> None:
    """Invalidate all mobile sessions after a password or device-security event."""
    index_key = f"attendance:student-session-index:{student_id}"
    try:
        keys = list(_client().smembers(index_key))
        pipe = _client().pipeline(transaction=True)
        if keys:
            pipe.delete(*keys)
        pipe.delete(index_key)
        pipe.execute()
    except RedisError:
        if get_settings().redis_required:
            _unavailable()
        keys = json.loads(_dev_get(index_key) or "[]")
        for key in keys:
            _DEV_CACHE.pop(key, None)
        _DEV_CACHE.pop(index_key, None)


def clear_development_state() -> None:
    """Test support: never permits deleting coordination data outside development."""
    if not get_settings().development_enabled:
        raise RuntimeError("Coordination state may only be cleared in development")
    _DEV_CACHE.clear()
    try:
        keys = list(_client().scan_iter(match="attendance:rate:*"))
        if keys:
            _client().delete(*keys)
    except RedisError:
        return


def publish_session_event(session_id: UUID, event_type: str) -> int:
    version_key = f"attendance:session:{session_id}:version"
    channel = f"attendance:session:{session_id}:events"
    payload = json.dumps({"event": event_type, "session_id": str(session_id), "at": int(time())})
    try:
        pipe = _client().pipeline(transaction=True)
        pipe.incr(version_key)
        pipe.expire(version_key, 60 * 60 * 24 * 8)
        pipe.publish(channel, payload)
        version, _, _ = pipe.execute()
        return int(version)
    except RedisError:
        if get_settings().redis_required:
            _unavailable()
        current = int(_dev_get(version_key) or "0") + 1
        _dev_set(version_key, str(current), 60 * 60 * 24 * 8)
        return current


def session_event_version(session_id: UUID) -> int:
    """Read the lightweight Redis version used by authenticated WebSocket clients."""
    key = f"attendance:session:{session_id}:version"
    try:
        return int(_client().get(key) or "0")
    except RedisError:
        if get_settings().redis_required:
            _unavailable()
        return int(_dev_get(key) or "0")
