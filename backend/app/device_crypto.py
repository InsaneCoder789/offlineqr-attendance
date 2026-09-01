from __future__ import annotations

import base64
import hashlib
from datetime import UTC, datetime
from uuid import UUID

from nacl.exceptions import BadSignatureError
from nacl.signing import VerifyKey


SUPPORTED_ALGORITHM = "Ed25519"


def canonical_timestamp(value: datetime) -> str:
    """Serialize protocol timestamps exactly as they are sent to clients."""
    return value.astimezone(UTC).isoformat().replace("+00:00", "Z")


def b64url_encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).decode("ascii").rstrip("=")


def b64url_decode(value: str) -> bytes:
    padding = "=" * ((4 - len(value) % 4) % 4)
    return base64.urlsafe_b64decode(value + padding)


def public_key_fingerprint(public_key_b64url: str) -> str:
    public_key = b64url_decode(public_key_b64url)
    if len(public_key) != 32:
        raise ValueError("Ed25519 public key must be 32 bytes")
    return hashlib.sha256(public_key).hexdigest()


def canonical_enrollment_payload(
    *,
    student_id: UUID,
    challenge_id: UUID,
    challenge: str,
    issued_at: str,
    public_key_fingerprint_value: str,
) -> bytes:
    return "\n".join(
        [
            "DEVICE_ENROLLMENT_V1",
            f"student_id:{student_id}",
            f"challenge_id:{challenge_id}",
            f"challenge:{challenge}",
            f"issued_at:{issued_at}",
            f"public_key_fingerprint:{public_key_fingerprint_value}",
        ]
    ).encode("utf-8")


def canonical_verification_payload(
    *,
    student_id: UUID,
    device_registration_id: UUID,
    challenge_id: UUID,
    challenge: str,
    issued_at: str,
    public_key_fingerprint_value: str,
) -> bytes:
    return "\n".join(
        [
            "DEVICE_VERIFICATION_V1",
            f"student_id:{student_id}",
            f"device_registration_id:{device_registration_id}",
            f"challenge_id:{challenge_id}",
            f"challenge:{challenge}",
            f"issued_at:{issued_at}",
            f"public_key_fingerprint:{public_key_fingerprint_value}",
        ]
    ).encode("utf-8")


def verify_signature(
    *,
    public_key_b64url: str,
    payload: bytes,
    signature_b64url: str,
) -> bool:
    try:
        VerifyKey(b64url_decode(public_key_b64url)).verify(
            payload,
            b64url_decode(signature_b64url),
        )
        return True
    except (BadSignatureError, ValueError):
        return False
