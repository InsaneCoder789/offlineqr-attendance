from __future__ import annotations

from datetime import UTC, datetime, timedelta
import re
import secrets
from uuid import UUID

import psycopg
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerifyMismatchError
from psycopg.rows import dict_row

from .config import get_settings
from .db import connect
from .errors import ApiError
from .redis_service import create_student_session, revoke_student_sessions


_PASSWORD_HASHER = PasswordHasher(time_cost=3, memory_cost=65536, parallelism=2)
_MAX_FAILED_LOGINS = 5
# Progressive lockout: a stranger typing a classmate's roll number cannot keep them out for long, while a
# sustained guessing run still ends at the full 15 minutes. Counter resets on a successful sign-in.
_LOCKOUT_STEPS = {5: timedelta(minutes=1), 6: timedelta(minutes=2), 7: timedelta(minutes=5)}
_LOCKOUT_MAX = timedelta(minutes=15)


# Unknown and locked accounts must cost the same Argon2 time as a real wrong password; otherwise response time
# reveals which identities exist (measured: 80 ms for a real roll number vs 8 ms for an unknown one).
_DUMMY_HASH = _PASSWORD_HASHER.hash("timing-equaliser-not-a-real-password")


def _burn_hash_time(password: str) -> None:
    try:
        _PASSWORD_HASHER.verify(_DUMMY_HASH, password)
    except (InvalidHashError, VerifyMismatchError):
        pass


def _lockout_for(failures: int) -> timedelta | None:
    if failures < _MAX_FAILED_LOGINS:
        return None
    return _LOCKOUT_STEPS.get(failures, _LOCKOUT_MAX)


def authenticate_student(roll_number: str, password: str) -> tuple[dict, str]:
    roll = _normalize_roll(roll_number)
    now = datetime.now(UTC)
    rejected = False
    with _connect() as conn:
        with conn.transaction():
            row = conn.execute(
                """
                SELECT s.id, s.roll_number, s.institutional_email, s.display_name,
                       sc.password_hash, sc.must_change_password, sc.failed_login_count, sc.locked_until
                FROM students s JOIN student_credentials sc ON sc.student_id = s.id
                WHERE s.roll_number = %s AND s.active = true FOR UPDATE
                """,
                [roll],
            ).fetchone()
            if row is None or (row["locked_until"] is not None and row["locked_until"] > now):
                _burn_hash_time(password)
                rejected = True
            else:
                try:
                    valid = _PASSWORD_HASHER.verify(row["password_hash"], password)
                except (InvalidHashError, VerifyMismatchError):
                    valid = False
                if not valid:
                    # Commit the failure counter; raising inside the transaction would roll it back.
                    failures = int(row["failed_login_count"]) + 1
                    lock = _lockout_for(failures)
                    locked_until = now + lock if lock else None
                    conn.execute(
                        "UPDATE student_credentials SET failed_login_count=%s, locked_until=%s, updated_at=now() WHERE student_id=%s",
                        [failures, locked_until, row["id"]],
                    )
                    rejected = True
                else:
                    rehash = _PASSWORD_HASHER.hash(password) if _PASSWORD_HASHER.check_needs_rehash(row["password_hash"]) else None
                    conn.execute(
                        """UPDATE student_credentials
                           SET failed_login_count=0, locked_until=NULL, last_login_at=now(),
                               password_hash=COALESCE(%s, password_hash), updated_at=now()
                           WHERE student_id=%s""",
                        [rehash, row["id"]],
                    )
                    profile = _profile(dict(row))
    if rejected:
        raise ApiError("INVALID_CREDENTIALS", "Invalid roll number or password.", 401)
    return profile, create_student_session(
        profile["id"], must_change_password=profile["must_change_password"]
    )


def change_student_password(student_id: UUID, current_password: str, new_password: str) -> None:
    _validate_new_password(new_password)
    with _connect() as conn:
        with conn.transaction():
            row = conn.execute("SELECT password_hash FROM student_credentials WHERE student_id=%s FOR UPDATE", [student_id]).fetchone()
            if row is None:
                raise ApiError("STUDENT_CREDENTIALS_NOT_FOUND", "Student credentials are unavailable.", 404)
            try:
                valid = _PASSWORD_HASHER.verify(row["password_hash"], current_password)
            except (InvalidHashError, VerifyMismatchError):
                valid = False
            if not valid:
                raise ApiError("INVALID_CURRENT_PASSWORD", "Current password is incorrect.", 400)
            conn.execute(
                """UPDATE student_credentials SET password_hash=%s, must_change_password=false,
                   password_changed_at=now(), failed_login_count=0, locked_until=NULL, updated_at=now()
                   WHERE student_id=%s""",
                [_PASSWORD_HASHER.hash(new_password), student_id],
            )
            revoke_student_sessions(student_id)


def reset_student_password_by_roll(roll_number: str, issued_by: str) -> str:
    """ICT-only recovery. The temporary value is returned once and never logged."""
    roll = _normalize_roll(roll_number)
    temporary_password = _temporary_password()
    with _connect() as conn:
        with conn.transaction():
            row = conn.execute(
                "SELECT id FROM students WHERE roll_number=%s AND active=true FOR UPDATE",
                [roll],
            ).fetchone()
            if row is None:
                raise ApiError("STUDENT_NOT_FOUND", "Student account is unavailable.", 404)
            credential = conn.execute(
                "SELECT student_id FROM student_credentials WHERE student_id=%s FOR UPDATE",
                [row["id"]],
            ).fetchone()
            if credential is None:
                conn.execute(
                    "INSERT INTO student_credentials (student_id, password_hash, must_change_password) VALUES (%s, %s, true)",
                    [row["id"], _PASSWORD_HASHER.hash(temporary_password)],
                )
            else:
                conn.execute(
                    """UPDATE student_credentials SET password_hash=%s, must_change_password=true,
                       failed_login_count=0, locked_until=NULL, updated_at=now() WHERE student_id=%s""",
                    [_PASSWORD_HASHER.hash(temporary_password), row["id"]],
                )
            conn.execute(
                """INSERT INTO audit_logs (actor_type, actor_id, event_type, entity_type, entity_id, metadata)
                   VALUES ('ICT_ADMIN', NULL, 'STUDENT_PASSWORD_RESET', 'student', %s, %s)""",
                [row["id"], psycopg.types.json.Jsonb({"issued_by": issued_by})],
            )
            revoke_student_sessions(row["id"])
    return temporary_password


def _profile(row: dict) -> dict:
    return {"id": row["id"], "roll_number": row["roll_number"], "institutional_email": row["institutional_email"], "display_name": row["display_name"], "must_change_password": bool(row.get("must_change_password", False))}


def _normalize_roll(value: str) -> str:
    roll = value.strip()
    if not re.fullmatch(r"[0-9]{5,12}", roll):
        raise ApiError("INVALID_CREDENTIALS", "Invalid roll number or password.", 401)
    return roll


def _validate_new_password(value: str) -> None:
    if len(value) < 14 or len(value) > 128:
        raise ApiError("WEAK_PASSWORD", "Use a password between 14 and 128 characters.", 400)
    kinds = sum((any(c.islower() for c in value), any(c.isupper() for c in value), any(c.isdigit() for c in value), any(not c.isalnum() for c in value)))
    if kinds < 3:
        raise ApiError("WEAK_PASSWORD", "Use at least three character types in the new password.", 400)


def _temporary_password() -> str:
    # 20 characters, four character classes, no student or device data embedded.
    return f"K!{secrets.token_urlsafe(16)}9a"


def _connect() -> psycopg.Connection:
    return connect()
