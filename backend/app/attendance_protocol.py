from __future__ import annotations

from datetime import UTC, datetime, timedelta
from uuid import UUID

from nacl.exceptions import BadSignatureError
from nacl.signing import SigningKey, VerifyKey

from .config import get_settings
from .device_crypto import b64url_decode, b64url_encode

ATTENDANCE_QR_PROTOCOL = "ATTENDANCE_QR_V1"
SESSION_AUTHORIZATION_PROTOCOL = "SESSION_AUTHORIZATION_V1"
ATTENDANCE_CLAIM_PROTOCOL = "ATTENDANCE_CLAIM_V1"
INSTITUTION_KEY_ID = "institution-root-2026-01"
QR_EPOCH_SECONDS = 5
CLAIM_SECONDS = 60
CLOCK_SKEW_SECONDS = 2


def utc_now() -> datetime:
    return datetime.now(UTC)


def institution_signing_key() -> SigningKey:
    return SigningKey(b64url_decode(get_settings().institution_signing_seed_b64url))


def institution_public_key() -> str:
    return b64url_encode(bytes(institution_signing_key().verify_key))


def epoch_for(now: datetime, origin: datetime) -> int:
    delta = now - origin
    return max(0, int(delta.total_seconds() // QR_EPOCH_SECONDS))


def epoch_window(origin: datetime, epoch: int) -> tuple[datetime, datetime]:
    issued = origin + timedelta(seconds=epoch * QR_EPOCH_SECONDS)
    return issued, issued + timedelta(seconds=QR_EPOCH_SECONDS)


def canonical_session_authorization(
    *,
    authorization_id: UUID,
    session_id: UUID,
    course_offering_id: UUID,
    faculty_id: UUID,
    valid_from: str,
    valid_until: str,
    key_id: str,
    session_public_key: str,
) -> bytes:
    return "\n".join(
        [
            SESSION_AUTHORIZATION_PROTOCOL,
            f"authorization_id:{authorization_id}",
            f"session_id:{session_id}",
            f"course_offering_id:{course_offering_id}",
            f"faculty_id:{faculty_id}",
            f"valid_from:{valid_from}",
            f"valid_until:{valid_until}",
            f"key_id:{key_id}",
            f"session_public_key:{session_public_key}",
        ]
    ).encode()


def canonical_attendance_qr(
    *,
    session_id: UUID,
    epoch: int,
    issued_at: str,
    expires_at: str,
    challenge: str,
    key_id: str,
) -> bytes:
    return "\n".join(
        [
            ATTENDANCE_QR_PROTOCOL,
            f"session_id:{session_id}",
            f"epoch:{epoch}",
            f"issued_at:{issued_at}",
            f"expires_at:{expires_at}",
            f"challenge:{challenge}",
            f"key_id:{key_id}",
        ]
    ).encode()


def canonical_attendance_claim(
    *,
    claim_id: UUID,
    session_id: UUID,
    student_id: UUID,
    device_registration_id: UUID,
    qr_epoch: int,
    qr_challenge: str,
    qr_captured_at: str,
    claim_created_at: str,
    claim_expires_at: str,
) -> bytes:
    return "\n".join(
        [
            ATTENDANCE_CLAIM_PROTOCOL,
            f"claim_id:{claim_id}",
            f"session_id:{session_id}",
            f"student_id:{student_id}",
            f"device_registration_id:{device_registration_id}",
            f"qr_epoch:{qr_epoch}",
            f"qr_challenge:{qr_challenge}",
            f"qr_captured_at:{qr_captured_at}",
            f"claim_created_at:{claim_created_at}",
            f"claim_expires_at:{claim_expires_at}",
        ]
    ).encode()


def sign(signing_key: SigningKey, payload: bytes) -> str:
    return b64url_encode(signing_key.sign(payload).signature)


def verify(public_key_b64url: str, payload: bytes, signature_b64url: str) -> bool:
    try:
        VerifyKey(b64url_decode(public_key_b64url)).verify(
            payload,
            b64url_decode(signature_b64url),
        )
        return True
    except (BadSignatureError, ValueError):
        return False
