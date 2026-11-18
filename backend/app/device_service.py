from __future__ import annotations

import secrets
from hashlib import sha256
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID

import psycopg
from psycopg import errors
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

from .config import get_settings
from .db import connect
from .device_crypto import (
    SUPPORTED_ALGORITHM,
    b64url_encode,
    canonical_enrollment_payload,
    canonical_timestamp,
    canonical_verification_payload,
    public_key_fingerprint,
    verify_signature,
)
from .device_attestation import verify_device_attestation
from .errors import ApiError
from .redis_service import consume_rate_limit

CHALLENGE_TTL_SECONDS = 300
CHALLENGE_RATE_LIMIT = 10
ACTIVATION_QR_TTL_SECONDS = 300


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
    device_profile: dict[str, Any],
    key_protection: str,
    attestation_provider: str | None = None,
    attestation_token: str | None = None,
) -> dict[str, Any]:
    if public_key_algorithm != SUPPORTED_ALGORITHM:
        raise ApiError("UNSUPPORTED_DEVICE_ALGORITHM", "Unsupported device key algorithm.", 400)

    fingerprint = _fingerprint_or_error(public_key)
    profile = _validated_device_profile(device_profile)
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
                issued_at=canonical_timestamp(challenge["issued_at"]),
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

            profile.update(
                verify_device_attestation(
                    provider=attestation_provider,
                    token=attestation_token,
                    platform=platform,
                    challenge_id=challenge_id,
                    public_key_fingerprint=fingerprint,
                )
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
                        manufacturer,
                        device_model,
                        os_version,
                        os_api_level,
                        is_physical_device,
                        integrity_status,
                        integrity_checked_at,
                        risk_flags,
                        key_protection,
                        status,
                        registered_at,
                        last_seen_at
                    )
                    VALUES (
                        %s, %s, %s, %s, %s, %s, %s,
                        %s, %s, %s, %s, %s, %s, now(), %s, %s,
                        'ACTIVE', now(), now()
                    )
                    RETURNING id, student_id, public_key_algorithm, key_fingerprint,
                              platform, display_label, status::text AS status,
                              registered_at, revoked_at, last_seen_at,
                              manufacturer, device_model, os_version, os_api_level,
                              is_physical_device, integrity_status, risk_flags
                    """,
                    [
                        student_id,
                        public_key,
                        public_key_algorithm,
                        fingerprint,
                        platform,
                        display_label,
                        Jsonb(app_instance_metadata),
                        profile["manufacturer"],
                        profile["model"],
                        profile["os_version"],
                        profile["os_api_level"],
                        profile["is_physical_device"],
                        profile["integrity_status"],
                        Jsonb(profile["risk_flags"]),
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
                {"key_fingerprint": fingerprint, "platform": platform, "device_profile": profile},
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
                issued_at=canonical_timestamp(challenge["issued_at"]),
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
    device_profile: dict[str, Any],
    key_protection: str,
    attestation_provider: str | None = None,
    attestation_token: str | None = None,
) -> dict[str, Any]:
    if public_key_algorithm != SUPPORTED_ALGORITHM:
        raise ApiError("UNSUPPORTED_DEVICE_ALGORITHM", "Unsupported device key algorithm.", 400)

    fingerprint = _fingerprint_or_error(public_key)
    profile = _validated_device_profile(device_profile)
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
                issued_at=canonical_timestamp(challenge["issued_at"]),
                public_key_fingerprint_value=fingerprint,
            )
            if not verify_signature(
                public_key_b64url=public_key,
                payload=payload,
                signature_b64url=signature,
            ):
                raise ApiError("INVALID_DEVICE_SIGNATURE", "Invalid replacement signature.", 400)

            profile.update(
                verify_device_attestation(
                    provider=attestation_provider,
                    token=attestation_token,
                    platform=platform,
                    challenge_id=challenge_id,
                    public_key_fingerprint=fingerprint,
                )
            )

            existing_request = conn.execute(
                """SELECT id FROM device_replacement_requests
                   WHERE student_id=%s AND status IN ('PENDING', 'APPROVED') FOR UPDATE""",
                [student_id],
            ).fetchone()
            if existing_request is not None:
                raise ApiError(
                    "REPLACEMENT_ALREADY_PENDING",
                    "A device replacement request is already awaiting completion.",
                    409,
                )

            pending = conn.execute(
                """
                INSERT INTO device_registrations (
                    student_id, public_key, public_key_algorithm, key_fingerprint,
                    platform, display_label, app_instance_metadata,
                    manufacturer, device_model, os_version, os_api_level,
                    is_physical_device, integrity_status, integrity_checked_at, risk_flags,
                    key_protection, status
                )
                VALUES (
                    %s, %s, %s, %s, %s, %s, %s,
                    %s, %s, %s, %s, %s, %s, now(), %s, %s, 'PENDING'
                )
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
                    profile["manufacturer"],
                    profile["model"],
                    profile["os_version"],
                    profile["os_api_level"],
                    profile["is_physical_device"],
                    profile["integrity_status"],
                    Jsonb(profile["risk_flags"]),
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
                    "device_profile": profile,
                },
            )
            return dict(request)


def approve_replacement(*, request_id: UUID, approved_by: str, decision_note: str) -> dict[str, Any]:
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

            updated = conn.execute(
                """
                UPDATE device_replacement_requests
                SET status = 'APPROVED', approved_at = now(), approved_by = %s,
                    decision_note = %s, decided_by = %s, decided_at = now(), updated_at = now()
                WHERE id = %s
                RETURNING id, student_id, old_device_registration_id,
                          new_device_registration_id, status::text AS status,
                          reason, requested_at, approved_at
                """,
                [approved_by, decision_note, approved_by, request_id],
            ).fetchone()
            _audit(
                conn,
                updated["student_id"],
                "DEVICE_REPLACEMENT_APPROVED",
                "device_replacement_request",
                request_id,
                {"approved_by": approved_by, "decision_note": decision_note},
            )
    return dict(updated)


def create_activation_qr(*, request_id: UUID, issued_by: str) -> dict[str, Any]:
    """Create a server-stateful, one-use QR after ICT explicitly approves a switch."""
    token = secrets.token_urlsafe(32)
    token_hash = sha256(token.encode("utf-8")).hexdigest()
    with _connect() as conn:
        with conn.transaction():
            request = conn.execute(
                """SELECT id, student_id, new_device_registration_id FROM device_replacement_requests
                   WHERE id=%s AND status='APPROVED' FOR UPDATE""",
                [request_id],
            ).fetchone()
            if request is None:
                raise ApiError("REPLACEMENT_NOT_APPROVED", "ICT must approve this device replacement first.", 409)
            existing = conn.execute(
                "SELECT id FROM device_activation_tokens WHERE replacement_request_id=%s AND consumed_at IS NULL FOR UPDATE",
                [request_id],
            ).fetchone()
            if existing is not None:
                conn.execute("DELETE FROM device_activation_tokens WHERE id=%s", [existing["id"]])
            row = conn.execute(
                """INSERT INTO device_activation_tokens
                   (student_id, replacement_request_id, new_device_registration_id, token_hash, issued_by, expires_at)
                   VALUES (%s, %s, %s, %s, %s, now() + (%s || ' seconds')::interval)
                   RETURNING expires_at""",
                [request["student_id"], request_id, request["new_device_registration_id"], token_hash, issued_by, ACTIVATION_QR_TTL_SECONDS],
            ).fetchone()
            _audit(conn, request["student_id"], "DEVICE_ACTIVATION_QR_ISSUED", "device_replacement_request", request_id, {"issued_by": issued_by})
            return {"replacement_request_id": request_id, "qr_payload": f"offlineqr-device-activate:{token}", "expires_at": row["expires_at"]}


def consume_activation_qr(*, student_id: UUID, qr_payload: str) -> dict[str, Any]:
    prefix = "offlineqr-device-activate:"
    if not qr_payload.startswith(prefix):
        raise ApiError("INVALID_DEVICE_ACTIVATION_QR", "This is not a Institution device activation QR.", 400)
    token = qr_payload.removeprefix(prefix)
    if not token or len(token) > 256:
        raise ApiError("INVALID_DEVICE_ACTIVATION_QR", "This device activation QR is invalid.", 400)
    token_hash = sha256(token.encode("utf-8")).hexdigest()
    with _connect() as conn:
        with conn.transaction():
            activation = conn.execute(
                """SELECT * FROM device_activation_tokens WHERE token_hash=%s FOR UPDATE""",
                [token_hash],
            ).fetchone()
            if activation is None or activation["student_id"] != student_id:
                raise ApiError("INVALID_DEVICE_ACTIVATION_QR", "This device activation QR is not for this student.", 403)
            if activation["consumed_at"] is not None:
                raise ApiError("DEVICE_ACTIVATION_ALREADY_USED", "This device activation QR was already used.", 409)
            if activation["expires_at"] <= datetime.now(UTC):
                raise ApiError("DEVICE_ACTIVATION_EXPIRED", "This device activation QR has expired.", 400)
            request = conn.execute(
                "SELECT * FROM device_replacement_requests WHERE id=%s AND status='APPROVED' FOR UPDATE",
                [activation["replacement_request_id"]],
            ).fetchone()
            if request is None or request["new_device_registration_id"] != activation["new_device_registration_id"]:
                raise ApiError("REPLACEMENT_NOT_APPROVED", "The device replacement cannot be activated.", 409)
            conn.execute("UPDATE device_registrations SET status='REVOKED', revoked_at=now(), updated_at=now() WHERE id=%s AND status='ACTIVE'", [request["old_device_registration_id"]])
            device = conn.execute(
                """UPDATE device_registrations SET status='ACTIVE', registered_at=now(), last_seen_at=now(), updated_at=now()
                   WHERE id=%s AND status='PENDING' RETURNING id, student_id, public_key_algorithm, key_fingerprint,
                   platform, display_label, status::text AS status, registered_at, revoked_at, last_seen_at,
                   manufacturer, device_model, os_version, os_api_level, is_physical_device, integrity_status, risk_flags""",
                [activation["new_device_registration_id"]],
            ).fetchone()
            if device is None:
                raise ApiError("REPLACEMENT_DEVICE_INVALID", "The replacement device is no longer available.", 409)
            conn.execute("UPDATE device_activation_tokens SET consumed_at=now(), consumed_by_device_registration_id=%s WHERE id=%s", [device["id"], activation["id"]])
            _audit(conn, student_id, "DEVICE_REPLACEMENT_ACTIVATED", "device_replacement_request", request["id"], {"new_device_registration_id": str(device["id"])})
            return dict(device)


def reject_replacement(*, request_id: UUID, rejected_by: str, decision_note: str) -> dict[str, Any]:
    with _connect() as conn:
        with conn.transaction():
            request = conn.execute(
                """
                SELECT * FROM device_replacement_requests
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
                WHERE id = %s AND status = 'PENDING'
                """,
                [request["new_device_registration_id"]],
            )
            updated = conn.execute(
                """
                UPDATE device_replacement_requests
                SET status = 'REJECTED', rejected_at = now(), decision_note = %s,
                    decided_by = %s, decided_at = now(), updated_at = now()
                WHERE id = %s
                RETURNING id, student_id, old_device_registration_id, new_device_registration_id,
                          status::text AS status, reason, requested_at, approved_at
                """,
                [decision_note, rejected_by, request_id],
            ).fetchone()
            _audit(
                conn,
                updated["student_id"],
                "DEVICE_REPLACEMENT_REJECTED",
                "device_replacement_request",
                request_id,
                {"rejected_by": rejected_by, "decision_note": decision_note},
            )
            return dict(updated)


def revoke_device(*, device_registration_id: UUID, revoked_by: str, reason: str) -> dict[str, Any]:
    with _connect() as conn:
        with conn.transaction():
            device = conn.execute(
                """
                SELECT id, student_id, status::text AS status
                FROM device_registrations WHERE id = %s FOR UPDATE
                """,
                [device_registration_id],
            ).fetchone()
            if device is None:
                raise ApiError("DEVICE_NOT_FOUND", "Device registration was not found.", 404)
            if device["status"] == "REVOKED":
                raise ApiError("DEVICE_ALREADY_REVOKED", "Device is already revoked.", 409)
            conn.execute(
                """
                UPDATE device_registrations
                SET status = 'REVOKED', revoked_at = now(), integrity_status = 'REVIEW_REQUIRED',
                    updated_at = now()
                WHERE id = %s
                """,
                [device_registration_id],
            )
            _audit(
                conn,
                device["student_id"],
                "DEVICE_REVOKED_BY_ADMIN",
                "device_registration",
                device_registration_id,
                {"revoked_by": revoked_by, "reason": reason},
            )
            return {"id": device_registration_id, "status": "REVOKED"}


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
            WHERE student_id = %s AND status IN ('PENDING', 'APPROVED')
            ORDER BY requested_at DESC
            LIMIT 1
            """,
            [student_id],
        ).fetchone()
        return dict(row) if row else None


def _connect() -> psycopg.Connection:
    return connect()


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
        return {
            **dict(row),
            "issued_at": canonical_timestamp(row["issued_at"]),
            "expires_at": canonical_timestamp(row["expires_at"]),
            "canonical_version": f"DEVICE_{purpose}_V1",
        }


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


def _validated_device_profile(profile: dict[str, Any]) -> dict[str, Any]:
    """Accept only privacy-safe device facts; hardware IDs never enter the protocol."""
    physical = profile.get("is_physical_device")
    emulator = profile.get("is_emulator")
    if emulator is True or physical is False:
        raise ApiError(
            "EMULATOR_NOT_ALLOWED",
            "Attendance registration requires a physical mobile device.",
            403,
        )
    manufacturer = _profile_text(profile.get("manufacturer"), 80)
    model = _profile_text(profile.get("model"), 120)
    os_version = _profile_text(profile.get("os_version"), 48)
    api_level = profile.get("os_api_level")
    if api_level is not None and (not isinstance(api_level, int) or not 1 <= api_level <= 100):
        raise ApiError("INVALID_DEVICE_PROFILE", "Invalid device OS level.", 400)
    risk_flags = ["INTEGRITY_UNVERIFIED"]
    if physical is None:
        risk_flags.append("PHYSICAL_STATUS_UNDECLARED")
    return {
        "manufacturer": manufacturer,
        "model": model,
        "os_version": os_version,
        "os_api_level": api_level,
        "is_physical_device": physical,
        "integrity_status": "DECLARED_PHYSICAL" if physical is True else "UNVERIFIED",
        "risk_flags": risk_flags,
    }


def _profile_text(value: Any, limit: int) -> str | None:
    if value is None:
        return None
    if not isinstance(value, str):
        raise ApiError("INVALID_DEVICE_PROFILE", "Invalid device profile field.", 400)
    normalized = value.strip()
    if len(normalized) > limit:
        raise ApiError("INVALID_DEVICE_PROFILE", "Device profile field is too long.", 400)
    return normalized or None


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
               registered_at, revoked_at, last_seen_at, manufacturer, device_model,
               os_version, os_api_level, is_physical_device, integrity_status, risk_flags
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
               registered_at, revoked_at, last_seen_at, manufacturer, device_model,
               os_version, os_api_level, is_physical_device, integrity_status, risk_flags
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
    result = consume_rate_limit(
        f"device-challenge:{purpose.lower()}",
        str(student_id),
        limit=CHALLENGE_RATE_LIMIT,
        window_seconds=60,
    )
    if not result.allowed:
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
