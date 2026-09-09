from __future__ import annotations

from typing import Any
from uuid import UUID

import httpx

from .config import get_settings
from .errors import ApiError


def verify_device_attestation(
    *,
    provider: str | None,
    token: str | None,
    platform: str,
    challenge_id: UUID,
    public_key_fingerprint: str,
) -> dict[str, Any]:
    """Verify Play Integrity/App Attest through an institution-controlled gateway."""
    settings = get_settings()
    if not provider or not token:
        if settings.device_attestation_required:
            raise ApiError("DEVICE_ATTESTATION_REQUIRED", "Device integrity verification is required.", 403)
        return {"integrity_status": "UNVERIFIED", "risk_flags": ["INTEGRITY_UNVERIFIED"]}
    expected_provider = "PLAY_INTEGRITY" if platform.upper() == "ANDROID" else "APPLE_APP_ATTEST"
    if provider != expected_provider:
        raise ApiError("DEVICE_ATTESTATION_INVALID", "Device attestation does not match the platform.", 403)
    if not settings.device_attestation_verifier_url:
        if settings.development_enabled and not settings.device_attestation_required:
            return {"integrity_status": "UNVERIFIED", "risk_flags": ["INTEGRITY_UNVERIFIED"]}
        raise ApiError("DEVICE_ATTESTATION_UNAVAILABLE", "Device integrity verification is unavailable.", 503)
    try:
        response = httpx.post(
            settings.device_attestation_verifier_url,
            headers={"Authorization": f"Bearer {settings.device_attestation_verifier_token}"},
            json={
                "provider": provider,
                "attestation_token": token,
                "platform": platform,
                "challenge_id": str(challenge_id),
                "public_key_fingerprint": public_key_fingerprint,
            },
            timeout=5.0,
        )
        response.raise_for_status()
        result = response.json()
    except (httpx.HTTPError, ValueError) as exc:
        raise ApiError("DEVICE_ATTESTATION_UNAVAILABLE", "Device integrity verification is unavailable.", 503) from exc
    if result.get("verified") is not True:
        raise ApiError("DEVICE_ATTESTATION_REJECTED", "This device did not pass integrity verification.", 403)
    if result.get("challenge_id") != str(challenge_id) or result.get("public_key_fingerprint") != public_key_fingerprint:
        raise ApiError("DEVICE_ATTESTATION_INVALID", "Device integrity response was not bound to this enrollment.", 403)
    return {"integrity_status": "VERIFIED", "risk_flags": []}
