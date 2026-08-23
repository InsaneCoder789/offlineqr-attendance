from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class DeviceChallengeOut(BaseModel):
    challenge_id: UUID
    challenge: str
    issued_at: datetime
    expires_at: datetime
    canonical_version: str


class EnrollmentCompleteIn(BaseModel):
    challenge_id: UUID
    public_key: str
    public_key_algorithm: str = "Ed25519"
    signature: str
    platform: str
    display_label: str | None = None
    app_instance_metadata: dict = Field(default_factory=dict)
    key_protection: str = "SOFTWARE_PROTECTED"


class DeviceRegistrationOut(BaseModel):
    id: UUID
    student_id: UUID
    public_key_algorithm: str
    key_fingerprint: str
    platform: str
    display_label: str | None
    status: str
    registered_at: datetime | None
    revoked_at: datetime | None
    last_seen_at: datetime | None


class VerificationChallengeIn(BaseModel):
    device_registration_id: UUID


class VerificationCompleteIn(BaseModel):
    challenge_id: UUID
    device_registration_id: UUID
    signature: str


class DeviceVerificationOut(BaseModel):
    device_registration_id: UUID
    status: str
    verified: bool


class ReplacementRequestIn(BaseModel):
    challenge_id: UUID
    public_key: str
    public_key_algorithm: str = "Ed25519"
    signature: str
    platform: str
    reason: str
    display_label: str | None = None
    app_instance_metadata: dict = Field(default_factory=dict)
    key_protection: str = "SOFTWARE_PROTECTED"


class ReplacementRequestOut(BaseModel):
    id: UUID
    student_id: UUID
    old_device_registration_id: UUID
    new_device_registration_id: UUID
    status: str
    reason: str
    requested_at: datetime
    approved_at: datetime | None

