from __future__ import annotations

import secrets
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID

import psycopg
from psycopg import errors
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

from .config import get_settings
from .device_crypto import (
    SUPPORTED_ALGORITHM,
    b64url_encode,
    canonical_enrollment_payload,
    canonical_verification_payload,
    public_key_fingerprint,
    verify_signature,
)
from .errors import ApiError

CHALLENGE_TTL_SECONDS = 300
CHALLENGE_RATE_LIMIT = 10


def create_enrollment_challenge(student_id: UUID) -> dict[str, Any]:
    _ensure_rate_limit(student_id, "ENROLLMENT")
    return _create_challenge(student_id=student_id, purpose="ENROLLMENT")


def create_replacement_challenge(student_id: UUID) -> dict[str, Any]:
    _ensure_rate_limit(student_id, "REPLACEMENT")
    return _create_challenge(student_id=student_id, purpose="REPLACEMENT")


def create_verification_challenge(
    *, student_id: UUID, device_registration_id: UUID
) -> dict[str, Any]:
    _ensure_rate_limit(student_id, "VERIFICATION")
    with _connect() as conn:
        device = _get_device_for_update(
            conn,
            student_id=student_id,
            device_registration_id=device_registration_id,
            lock=False,
        )
        if device["status"] == "REVOKED":
            _audit(
                conn,
                student_id,
                "DEVICE_VERIFICATION_FAILED",
                "device_registration",
                device_registration_id,
                {"reason": "DEVICE_REVOKED"},
            )
            raise ApiError("DEVICE_REVOKED", "Device registration is revoked.", 403)
    return _create_challenge(
        student_id=student_id,
        purpose="VERIFICATION",
        device_registration_id=device_registration_id,
    )


def complete_enrollment(
    *,
    student_id: UUID,
    challenge_id: UUID,
    public_key: str,
    public_key_algorithm: str,
    signature: str,
    platform: str,
    display_label: str | None,
    app_instance_metadata: dict,
    key_protection: str,
) -> dict[str, Any]:
    if public_key_algorithm != SUPPORTED_ALGORITHM:
        raise ApiError("UNSUPPORTED_DEVICE_ALGORITHM", "Unsupported device key algorithm.", 400)

    fingerprint = _fingerprint_or_error(public_key)
    with _connect() as conn:
        with conn.transaction():
            challenge = _consume_challenge(
                conn,
                student_id=student_id,
                challenge_id=challenge_id,
                purpose="ENROLLMENT",
            )
            payload = canonical_enrollment_payload(
                student_id=student_id,
                challenge_id=challenge_id,
                challenge=challenge["challenge"],
                issued_at=challenge["issued_at"].isoformat(),
                public_key_fingerprint_value=fingerprint,
            )
            if not verify_signature(
                public_key_b64url=public_key,
                payload=payload,
                signature_b64url=signature,
            ):
                _audit(
                    conn,
                    student_id,
                    "DEVICE_VERIFICATION_FAILED",
                    "device_challenge",
                    challenge_id,
                    {"reason": "INVALID_DEVICE_SIGNATURE"},
                )
                raise ApiError(
                    "INVALID_DEVICE_SIGNATURE",
                    "Device signature could not be verified.",
                    400,
                )

            active = _active_device(conn, student_id)
            if active is not None:
                _audit(
                    conn,
                    student_id,
                    "DEVICE_CONFLICT",
                    "device_registration",
                    active["id"],
                    {"reason": "ACTIVE_DEVICE_EXISTS"},
                )
                raise ApiError(
                    "ACTIVE_DEVICE_EXISTS",
                    "This student already has an active attendance device.",
                    409,
                )

            try:
                device = conn.execute(
                    """
                    INSERT INTO device_registrations (
                        student_id,
                        public_key,
                        public_key_algorithm,
                        key_fingerprint,
                        platform,
                        display_label,
                        app_instance_metadata,
                        key_protection,
                        status,
                        registered_at,
                        last_seen_at
                    )
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, 'ACTIVE', now(), now())
                    RETURNING id, student_id, public_key_algorithm, key_fingerprint,
                              platform, display_label, status::text AS status,
                              registered_at, revoked_at, last_seen_at
                    """,
                    [
                        student_id,
                        public_key,
                        public_key_algorithm,
                        fingerprint,
                        platform,
                        display_label,
                        Jsonb(app_instance_metadata),
                        key_protection,
                    ],
                ).fetchone()
            except errors.UniqueViolation as exc:
                raise ApiError(
                    "ACTIVE_DEVICE_EXISTS",
                    "This student already has an active attendance device.",
                    409,
                ) from exc

            _audit(
                conn,
                student_id,
                "DEVICE_REGISTERED",
                "device_registration",
                device["id"],
                {"key_fingerprint": fingerprint, "platform": platform},
            )
            return dict(device)


def complete_verification(
    *,
    student_id: UUID,
    challenge_id: UUID,
    device_registration_id: UUID,
    signature: str,
) -> dict[str, Any]:
    with _connect() as conn:
        with conn.transaction():
            device = _get_device_for_update(
                conn,
                student_id=student_id,
                device_registration_id=device_registration_id,
                lock=True,
            )
            if device["status"] == "REVOKED":
                raise ApiError("DEVICE_REVOKED", "Device registration is revoked.", 403)
            challenge = _consume_challenge(
                conn,
                student_id=student_id,
                challenge_id=challenge_id,
                purpose="VERIFICATION",
                device_registration_id=device_registration_id,
            )
            payload = canonical_verification_payload(
                student_id=student_id,
                device_registration_id=device_registration_id,
                challenge_id=challenge_id,
                challenge=challenge["challenge"],
                issued_at=challenge["issued_at"].isoformat(),
                public_key_fingerprint_value=device["key_fingerprint"],
            )
            verified = verify_signature(
                public_key_b64url=device["public_key"],
                payload=payload,
                signature_b64url=signature,
            )
            if not verified:
                _audit(
                    conn,
                    student_id,
                    "DEVICE_VERIFICATION_FAILED",
                    "device_registration",
                    device_registration_id,
                    {"reason": "INVALID_DEVICE_SIGNATURE"},
                )
                raise ApiError("INVALID_DEVICE_SIGNATURE", "Invalid device signature.", 400)

            conn.execute(
                "UPDATE device_registrations SET last_seen_at = now(), updated_at = now() WHERE id = %s",
                [device_registration_id],
            )
            _audit(
                conn,
                student_id,
                "DEVICE_VERIFIED",
                "device_registration",
                device_registration_id,
                {"key_fingerprint": device["key_fingerprint"]},
            )
            return {
                "device_registration_id": device_registration_id,
                "status": device["status"],
                "verified": True,
            }


def request_replacement(
    *,
    student_id: UUID,
    challenge_id: UUID,
    public_key: str,
    public_key_algorithm: str,
    signature: str,
    platform: str,
    reason: str,
    display_label: str | None,
    app_instance_metadata: dict,
    key_protection: str,
) -> dict[str, Any]:
    if public_key_algorithm != SUPPORTED_ALGORITHM:
        raise ApiError("UNSUPPORTED_DEVICE_ALGORITHM", "Unsupported device key algorithm.", 400)

    fingerprint = _fingerprint_or_error(public_key)
    with _connect() as conn:
        with conn.transaction():
            active = _active_device(conn, student_id, lock=True)
            if active is None:
                raise ApiError("DEVICE_NOT_FOUND", "No active device exists to replace.", 404)

            challenge = _consume_challenge(
                conn,
                student_id=student_id,
                challenge_id=challenge_id,
                purpose="REPLACEMENT",
            )
            payload = canonical_enrollment_payload(
                student_id=student_id,
                challenge_id=challenge_id,
                challenge=challenge["challenge"],
                issued_at=challenge["issued_at"].isoformat(),
                public_key_fingerprint_value=fingerprint,
            )
            if not verify_signature(
                public_key_b64url=public_key,
                payload=payload,
                signature_b64url=signature,
            ):
                raise ApiError("INVALID_DEVICE_SIGNATURE", "Invalid replacement signature.", 400)

            pending = conn.execute(
                """
                INSERT INTO device_registrations (
                    student_id, public_key, public_key_algorithm, key_fingerprint,
                    platform, display_label, app_instance_metadata, key_protection, status
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, 'PENDING')
                RETURNING id
                """,
                [
                    student_id,
                    public_key,
                    public_key_algorithm,
                    fingerprint,
                    platform,
                    display_label,
                    Jsonb(app_instance_metadata),
                    key_protection,
                ],
            ).fetchone()

            try:
                request = conn.execute(
                    """
                    INSERT INTO device_replacement_requests (
                        student_id,
                        old_device_registration_id,
                        new_device_registration_id,
                        reason
                    )
                    VALUES (%s, %s, %s, %s)
                    RETURNING id, student_id, old_device_registration_id,
                              new_device_registration_id, status::text AS status,
                              reason, requested_at, approved_at
                    """,
                    [student_id, active["id"], pending["id"], reason],
                ).fetchone()
            except errors.UniqueViolation as exc:
                raise ApiError(
                    "REPLACEMENT_ALREADY_PENDING",
                    "A device replacement request is already pending.",
                    409,
                ) from exc

            _audit(
                conn,
                student_id,
                "DEVICE_REPLACEMENT_REQUESTED",
                "device_replacement_request",
                request["id"],
                {
                    "old_device_registration_id": str(active["id"]),
                    "new_device_registration_id": str(pending["id"]),
                },
            )
            return dict(request)


def approve_replacement(*, request_id: UUID, approved_by: str) -> dict[str, Any]:
    with _connect() as conn:
        with conn.transaction():
            request = conn.execute(
                """
                SELECT *
                FROM device_replacement_requests
                WHERE id = %s AND status = 'PENDING'
                FOR UPDATE
                """,
                [request_id],
            ).fetchone()
            if request is None:
                raise ApiError("REPLACEMENT_NOT_FOUND", "Pending replacement request was not found.", 404)

            conn.execute(
                """
                UPDATE device_registrations
                SET status = 'REVOKED', revoked_at = now(), updated_at = now()
                WHERE id = %s AND status = 'ACTIVE'
                """,
                [request["old_device_registration_id"]],
            )
            conn.execute(
                """
                UPDATE device_registrations
                SET status = 'ACTIVE', registered_at = now(), last_seen_at = now(), updated_at = now()
                WHERE id = %s AND status = 'PENDING'
                """,
                [request["new_device_registration_id"]],
            )
            updated = conn.execute(
                """
                UPDATE device_replacement_requests
                SET status = 'APPROVED', approved_at = now(), approved_by = %s, updated_at = now()
                WHERE id = %s
                RETURNING id, student_id, old_device_registration_id,
                          new_device_registration_id, status::text AS status,
                          reason, requested_at, approved_at
                """,
                [approved_by, request_id],
            ).fetchone()
            _audit(
                conn,
                updated["student_id"],
                "DEVICE_REPLACEMENT_APPROVED",
                "device_replacement_request",
                request_id,
                {"approved_by": approved_by},
            )
            return dict(updated)


def current_device(student_id: UUID) -> dict[str, Any] | None:
    with _connect() as conn:
        row = _active_device(conn, student_id)
        return dict(row) if row else None


def current_replacement_request(student_id: UUID) -> dict[str, Any] | None:
    with _connect() as conn:
        row = conn.execute(
            """
            SELECT id, student_id, old_device_registration_id, new_device_registration_id,
                   status::text AS status, reason, requested_at, approved_at
            FROM device_replacement_requests
            WHERE student_id = %s AND status = 'PENDING'
            ORDER BY requested_at DESC
            LIMIT 1
            """,
            [student_id],
        ).fetchone()
        return dict(row) if row else None


def _connect() -> psycopg.Connection:
    return psycopg.connect(get_settings().database_url, row_factory=dict_row)


def _create_challenge(
    *,
    student_id: UUID,
    purpose: str,
    device_registration_id: UUID | None = None,
) -> dict[str, Any]:
    challenge = b64url_encode(secrets.token_bytes(32))
    with _connect() as conn:
        row = conn.execute(
            """
            INSERT INTO device_challenges (
                student_id,
                device_registration_id,
                purpose,
                challenge,
                expires_at
            )
            VALUES (%s, %s, %s, %s, now() + (%s || ' seconds')::interval)
            RETURNING id AS challenge_id, challenge, issued_at, expires_at
            """,
            [
                student_id,
                device_registration_id,
                purpose,
                challenge,
                CHALLENGE_TTL_SECONDS,
            ],
        ).fetchone()
        event_type = {
            "ENROLLMENT": "DEVICE_ENROLLMENT_STARTED",
            "VERIFICATION": "DEVICE_VERIFICATION_STARTED",
            "REPLACEMENT": "DEVICE_REPLACEMENT_STARTED",
        }[purpose]
        _audit(
            conn,
            student_id,
            event_type,
            "device_challenge",
            row["challenge_id"],
            {"purpose": purpose},
        )
        conn.commit()
        return {**dict(row), "canonical_version": f"DEVICE_{purpose}_V1"}


def _consume_challenge(
    conn: psycopg.Connection,
    *,
    student_id: UUID,
    challenge_id: UUID,
    purpose: str,
    device_registration_id: UUID | None = None,
) -> dict[str, Any]:
    challenge = conn.execute(
        """
        SELECT id, challenge, issued_at, expires_at, used_at
        FROM device_challenges
        WHERE id = %s
          AND student_id = %s
          AND purpose = %s
          AND (%s::uuid IS NULL OR device_registration_id = %s)
        FOR UPDATE
        """,
        [challenge_id, student_id, purpose, device_registration_id, device_registration_id],
    ).fetchone()
    if challenge is None:
        raise ApiError("DEVICE_CHALLENGE_NOT_FOUND", "Device challenge was not found.", 404)
    if challenge["used_at"] is not None:
        raise ApiError("CHALLENGE_ALREADY_USED", "Device challenge was already used.", 409)
    if challenge["expires_at"] <= datetime.now(UTC):
        raise ApiError("CHALLENGE_EXPIRED", "Device challenge expired.", 400)
    conn.execute(
        "UPDATE device_challenges SET used_at = now() WHERE id = %s",
        [challenge_id],
    )
    return dict(challenge)


def _active_device(
    conn: psycopg.Connection,
    student_id: UUID,
    *,
    lock: bool = False,
) -> dict[str, Any] | None:
    suffix = "FOR UPDATE" if lock else ""
    return conn.execute(
        f"""
        SELECT id, student_id, public_key, public_key_algorithm, key_fingerprint,
               platform, display_label, status::text AS status,
               registered_at, revoked_at, last_seen_at
        FROM device_registrations
        WHERE student_id = %s AND status = 'ACTIVE'
        {suffix}
        """,
        [student_id],
    ).fetchone()


def _get_device_for_update(
    conn: psycopg.Connection,
    *,
    student_id: UUID,
    device_registration_id: UUID,
    lock: bool,
) -> dict[str, Any]:
    suffix = "FOR UPDATE" if lock else ""
    row = conn.execute(
        f"""
        SELECT id, student_id, public_key, public_key_algorithm, key_fingerprint,
               platform, display_label, status::text AS status,
               registered_at, revoked_at, last_seen_at
        FROM device_registrations
        WHERE id = %s AND student_id = %s
        {suffix}
        """,
        [device_registration_id, student_id],
    ).fetchone()
    if row is None:
        raise ApiError("DEVICE_NOT_FOUND", "Device registration was not found.", 404)
    return dict(row)


def _ensure_rate_limit(student_id: UUID, purpose: str) -> None:
    with _connect() as conn:
        count = conn.execute(
            """
            SELECT COUNT(*)::int AS count
            FROM device_challenges
            WHERE student_id = %s
              AND purpose = %s
              AND issued_at > now() - interval '1 minute'
            """,
            [student_id, purpose],
        ).fetchone()["count"]
        if count >= CHALLENGE_RATE_LIMIT:
            raise ApiError("RATE_LIMITED", "Too many device challenge requests.", 429)


def _fingerprint_or_error(public_key: str) -> str:
    try:
        return public_key_fingerprint(public_key)
    except ValueError as exc:
        raise ApiError("MALFORMED_DEVICE_PUBLIC_KEY", str(exc), 400) from exc


def _audit(
    conn: psycopg.Connection,
    student_id: UUID,
    event_type: str,
    entity_type: str,
    entity_id: UUID,
    metadata: dict[str, Any],
) -> None:
    conn.execute(
        """
        INSERT INTO audit_logs (
            actor_type,
            actor_id,
            event_type,
            entity_type,
            entity_id,
            metadata
        )
        VALUES ('STUDENT', %s, %s, %s, %s, %s)
        """,
        [
            student_id,
            event_type,
            entity_type,
            entity_id,
            Jsonb(metadata),
        ],
    )
