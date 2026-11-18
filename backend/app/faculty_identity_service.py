from __future__ import annotations

from datetime import UTC, datetime, timedelta
import re
from uuid import UUID

import psycopg
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerifyMismatchError
from psycopg.rows import dict_row

from .config import get_settings
from .db import connect
from .errors import ApiError
from .institution_identity import institution_email_allowed
from .redis_service import create_faculty_session, revoke_faculty_sessions


_PASSWORD_HASHER = PasswordHasher(time_cost=3, memory_cost=65536, parallelism=2)
_MAX_FAILED_LOGINS = 5
_LOCKOUT_DURATION = timedelta(minutes=15)
_PHONE_PATTERN = re.compile(r"^\+?[0-9][0-9 -]{6,23}$")


def hash_password(value: str) -> str:
    _validate_new_password(value)
    return _PASSWORD_HASHER.hash(value)


def authenticate_faculty(email: str, password: str) -> tuple[dict, str, str]:
    normalized_email = _normalize_email(email)
    now = datetime.now(UTC)
    rejected = False
    with _connect() as conn:
        with conn.transaction():
            row = conn.execute(
                """
                SELECT f.id, f.employee_code, f.institutional_email, f.display_name, f.phone_number,
                       f.designation, f.org_unit,
                       f.access_role,
                       fc.password_hash, fc.must_change_password, fc.failed_login_count, fc.locked_until
                FROM faculty f
                JOIN faculty_credentials fc ON fc.faculty_id = f.id
                WHERE lower(f.institutional_email) = %s AND f.active = true
                FOR UPDATE
                """,
                [normalized_email],
            ).fetchone()
            if row is None or (row["locked_until"] is not None and row["locked_until"] > now):
                rejected = True
            else:
                try:
                    valid = _PASSWORD_HASHER.verify(row["password_hash"], password)
                except (InvalidHashError, VerifyMismatchError):
                    valid = False
                if not valid:
                    # Commit the failure counter; raising inside the transaction would roll it back.
                    failures = int(row["failed_login_count"]) + 1
                    locked_until = now + _LOCKOUT_DURATION if failures >= _MAX_FAILED_LOGINS else None
                    conn.execute(
                        """
                        UPDATE faculty_credentials
                        SET failed_login_count = %s, locked_until = %s, updated_at = now()
                        WHERE faculty_id = %s
                        """,
                        [failures, locked_until, row["id"]],
                    )
                    rejected = True
                else:
                    replacement_hash = _PASSWORD_HASHER.hash(password) if _PASSWORD_HASHER.check_needs_rehash(row["password_hash"]) else None
                    conn.execute(
                        """
                        UPDATE faculty_credentials
                        SET failed_login_count = 0, locked_until = NULL, last_login_at = now(),
                            password_hash = COALESCE(%s, password_hash), updated_at = now()
                        WHERE faculty_id = %s
                        """,
                        [replacement_hash, row["id"]],
                    )
                    profile = _profile(dict(row))
    if rejected:
        raise ApiError("INVALID_CREDENTIALS", "Invalid faculty email or password.", 401)
    token, csrf_token = create_faculty_session(profile["id"])
    return profile, token, csrf_token


def faculty_profile(faculty_id: UUID) -> dict:
    with _connect() as conn:
        row = conn.execute(
            """
            SELECT f.id, f.employee_code, f.institutional_email, f.display_name, f.phone_number,
                   f.designation, f.org_unit,
                   f.access_role,
                   fc.must_change_password, fc.password_changed_at, fc.last_login_at
            FROM faculty f
            JOIN faculty_credentials fc ON fc.faculty_id = f.id
            WHERE f.id = %s AND f.active = true
            """,
            [faculty_id],
        ).fetchone()
    if row is None:
        raise ApiError("FACULTY_NOT_FOUND", "Faculty account is unavailable.", 404)
    return _profile(dict(row))


def update_faculty_profile(faculty_id: UUID, display_name: str, phone_number: str | None) -> dict:
    normalized_name = " ".join(display_name.split())
    if not 2 <= len(normalized_name) <= 120:
        raise ApiError("INVALID_PROFILE_NAME", "Use a faculty name between 2 and 120 characters.", 400)
    normalized_phone = _normalize_phone(phone_number)
    with _connect() as conn:
        with conn.transaction():
            row = conn.execute(
                """
                UPDATE faculty
                SET display_name = %s, phone_number = %s, profile_updated_at = now(), updated_at = now()
                WHERE id = %s AND active = true
                RETURNING id
                """,
                [normalized_name, normalized_phone, faculty_id],
            ).fetchone()
            if row is None:
                raise ApiError("FACULTY_NOT_FOUND", "Faculty account is unavailable.", 404)
    return faculty_profile(faculty_id)


def change_faculty_password(faculty_id: UUID, current_password: str, new_password: str) -> None:
    _validate_new_password(new_password)
    with _connect() as conn:
        with conn.transaction():
            row = conn.execute(
                "SELECT password_hash FROM faculty_credentials WHERE faculty_id = %s FOR UPDATE",
                [faculty_id],
            ).fetchone()
            if row is None:
                raise ApiError("FACULTY_CREDENTIALS_NOT_FOUND", "Faculty credentials are unavailable.", 404)
            try:
                valid = _PASSWORD_HASHER.verify(row["password_hash"], current_password)
            except (InvalidHashError, VerifyMismatchError):
                valid = False
            if not valid:
                raise ApiError("INVALID_CURRENT_PASSWORD", "Current password is incorrect.", 400)
            conn.execute(
                """
                UPDATE faculty_credentials
                SET password_hash = %s, must_change_password = false, password_changed_at = now(),
                    failed_login_count = 0, locked_until = NULL, updated_at = now()
                WHERE faculty_id = %s
                """,
                [_PASSWORD_HASHER.hash(new_password), faculty_id],
            )
            revoke_faculty_sessions(faculty_id)


def _profile(row: dict) -> dict:
    return {
        "id": row["id"],
        "employee_code": row.get("employee_code"),
        "institutional_email": row["institutional_email"],
        "display_name": row["display_name"],
        "phone_number": row.get("phone_number"),
        "designation": row.get("designation"),
        "org_unit": row.get("org_unit"),
        "access_role": row.get("access_role", "FACULTY"),
        "must_change_password": bool(row.get("must_change_password", False)),
        "password_changed_at": row.get("password_changed_at"),
        "last_login_at": row.get("last_login_at"),
    }


def _normalize_email(value: str) -> str:
    email = value.strip().lower()
    if not institution_email_allowed(email):
        raise ApiError("INVALID_CREDENTIALS", "Invalid faculty email or password.", 401)
    return email


def _normalize_phone(value: str | None) -> str | None:
    if value is None or not value.strip():
        return None
    normalized = value.strip()
    if not _PHONE_PATTERN.fullmatch(normalized):
        raise ApiError("INVALID_PHONE_NUMBER", "Use a valid phone number.", 400)
    return normalized


def _validate_new_password(value: str) -> None:
    if len(value) < 14 or len(value) > 128:
        raise ApiError("WEAK_PASSWORD", "Use a password between 14 and 128 characters.", 400)
    kinds = sum((any(char.islower() for char in value), any(char.isupper() for char in value), any(char.isdigit() for char in value), any(not char.isalnum() for char in value)))
    if kinds < 3:
        raise ApiError("WEAK_PASSWORD", "Use at least three character types in the new password.", 400)


def _connect() -> psycopg.Connection:
    return connect()
