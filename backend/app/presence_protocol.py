from __future__ import annotations

from uuid import UUID

PRESENCE_CHALLENGE_PROTOCOL = "PRESENCE_CHALLENGE_V1"
PRESENCE_RESPONSE_PROTOCOL = "PRESENCE_RESPONSE_V1"
ATTENDANCE_PROOF_PROTOCOL = "ATTENDANCE_PROOF_V1"
PRESENCE_EPOCH_SECONDS = 10
PRESENCE_CHALLENGE_SECONDS = 20
PRIMARY_PRESENCE_TRANSPORT = "QR_ASSISTED_WEBRTC_DATA_CHANNEL"


def canonical_presence_challenge(
    *,
    challenge_id: UUID,
    session_id: UUID,
    claim_id: UUID,
    presence_epoch: int,
    nonce: str,
    issued_at: str,
    expires_at: str,
    transport: str,
    host_public_key: str,
) -> bytes:
    return "\n".join(
        [
            PRESENCE_CHALLENGE_PROTOCOL,
            f"challenge_id:{challenge_id}",
            f"session_id:{session_id}",
            f"claim_id:{claim_id}",
            f"presence_epoch:{presence_epoch}",
            f"nonce:{nonce}",
            f"issued_at:{issued_at}",
            f"expires_at:{expires_at}",
            f"transport:{transport}",
            f"host_public_key:{host_public_key}",
        ]
    ).encode("utf-8")


def canonical_presence_response(
    *,
    response_id: UUID,
    challenge_id: UUID,
    session_id: UUID,
    claim_id: UUID,
    device_registration_id: UUID,
    presence_epoch: int,
    responded_at: str,
    transport: str,
    challenge_nonce: str,
    host_public_key: str,
) -> bytes:
    return "\n".join(
        [
            PRESENCE_RESPONSE_PROTOCOL,
            f"response_id:{response_id}",
            f"challenge_id:{challenge_id}",
            f"session_id:{session_id}",
            f"claim_id:{claim_id}",
            f"device_registration_id:{device_registration_id}",
            f"presence_epoch:{presence_epoch}",
            f"responded_at:{responded_at}",
            f"transport:{transport}",
            f"challenge_nonce:{challenge_nonce}",
            f"host_public_key:{host_public_key}",
        ]
    ).encode("utf-8")


def canonical_attendance_proof(
    *,
    proof_id: UUID,
    claim_id: UUID,
    session_id: UUID,
    student_id: UUID,
    device_registration_id: UUID,
    presence_challenge_id: UUID,
    presence_response_id: UUID,
    proof_created_at: str,
) -> bytes:
    return "\n".join(
        [
            ATTENDANCE_PROOF_PROTOCOL,
            f"proof_id:{proof_id}",
            f"claim_id:{claim_id}",
            f"session_id:{session_id}",
            f"student_id:{student_id}",
            f"device_registration_id:{device_registration_id}",
            f"presence_challenge_id:{presence_challenge_id}",
            f"presence_response_id:{presence_response_id}",
            f"proof_created_at:{proof_created_at}",
        ]
    ).encode("utf-8")
