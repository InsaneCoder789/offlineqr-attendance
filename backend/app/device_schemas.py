from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field, field_validator


class DeviceProfileIn(BaseModel):
    """Privacy-minimized facts declared by the attendance app, never raw hardware IDs."""

    manufacturer: str | None = Field(default=None, max_length=80)
    model: str | None = Field(default=None, max_length=120)
    os_version: str | None = Field(default=None, max_length=48)
    os_api_level: int | None = Field(default=None, ge=1, le=100)
    app_version: str | None = Field(default=None, max_length=48)
    is_physical_device: bool | None = None
    is_emulator: bool | None = None

    @field_validator("manufacturer", "model", "os_version", "app_version")
    @classmethod
    def normalize_optional_text(cls, value: str | None) -> str | None:
        return value.strip() if value else None


class DeviceChallengeOut(BaseModel):
    challenge_id: UUID
    challenge: str
    # Protocol values, not presentation dates. These exact UTC strings are signed.
    issued_at: str
    expires_at: str
    canonical_version: str


class EnrollmentCompleteIn(BaseModel):
    challenge_id: UUID
    public_key: str
    public_key_algorithm: str = "Ed25519"
    signature: str
    platform: str
    display_label: str | None = None
    app_instance_metadata: dict = Field(default_factory=dict)
    device_profile: DeviceProfileIn = Field(default_factory=DeviceProfileIn)
    key_protection: str = "SOFTWARE_PROTECTED"
    attestation_provider: str | None = Field(default=None, pattern="^(PLAY_INTEGRITY|APPLE_APP_ATTEST)$")
    attestation_token: str | None = Field(default=None, min_length=32, max_length=16384)


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
    manufacturer: str | None = None
    device_model: str | None = None
    os_version: str | None = None
    os_api_level: int | None = None
    is_physical_device: bool | None = None
    integrity_status: str = "UNVERIFIED"
    risk_flags: list[str] = Field(default_factory=list)


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
    device_profile: DeviceProfileIn = Field(default_factory=DeviceProfileIn)
    key_protection: str = "SOFTWARE_PROTECTED"
    attestation_provider: str | None = Field(default=None, pattern="^(PLAY_INTEGRITY|APPLE_APP_ATTEST)$")
    attestation_token: str | None = Field(default=None, min_length=32, max_length=16384)


class ReplacementRequestOut(BaseModel):
    id: UUID
    student_id: UUID
    old_device_registration_id: UUID
    new_device_registration_id: UUID
    status: str
    reason: str
    requested_at: datetime
    approved_at: datetime | None


class DeviceActivationQrOut(BaseModel):
    replacement_request_id: UUID
    qr_payload: str
    expires_at: datetime


class DeviceActivationConsumeIn(BaseModel):
    qr_payload: str = Field(min_length=32, max_length=512)


class AdminDeviceSummaryOut(BaseModel):
    id: UUID
    device_reference: str
    student_id: UUID
    roll_number: str
    student_name: str
    section_code: str
    status: str
    platform: str
    manufacturer: str | None = None
    device_model: str | None = None
    os_version: str | None = None
    is_physical_device: bool | None = None
    integrity_status: str
    risk_flags: list[str] = Field(default_factory=list)
    display_label: str | None = None
    registered_at: datetime | None = None
    last_seen_at: datetime | None = None
    pending_replacement_id: UUID | None = None


class AdminDeviceDetailOut(AdminDeviceSummaryOut):
    key_fingerprint: str
    revoked_at: datetime | None = None
    app_instance_metadata: dict = Field(default_factory=dict)


class AdminDeviceHistoryOut(BaseModel):
    id: UUID
    event_type: str
    actor_type: str
    occurred_at: datetime
    correlation_id: str
    metadata: dict = Field(default_factory=dict)


class AdminDeviceStatsOut(BaseModel):
    total_devices: int
    active_devices: int
    pending_replacements: int
    review_required: int
    revoked_devices: int


class AdminDecisionIn(BaseModel):
    note: str = Field(min_length=3, max_length=280)


class AdminRevokeIn(BaseModel):
    reason: str = Field(min_length=3, max_length=280)
