from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator


class TimetableEntryOut(BaseModel):
    id: UUID
    course_offering_id: UUID
    day_of_week: int
    start_time: str
    end_time: str
    room: str
    valid_from: str
    valid_until: str


class FacultyClassOut(BaseModel):
    course_offering_id: UUID
    course_code: str
    course_name: str
    section_code: str
    room: str
    start_time: str
    end_time: str
    offline_ready: bool


class FacultyLoginIn(BaseModel):
    email: str
    password: str


class FacultyLoginOut(BaseModel):
    id: UUID
    employee_code: str | None
    institutional_email: str
    display_name: str
    phone_number: str | None = None
    designation: str | None = None
    org_unit: str | None = None
    access_role: str = "FACULTY"
    must_change_password: bool = False
    password_changed_at: datetime | None = None
    last_login_at: datetime | None = None


class FacultyProfileUpdateIn(BaseModel):
    display_name: str = Field(min_length=2, max_length=120)
    phone_number: str | None = Field(default=None, max_length=24)


class FacultyPasswordChangeIn(BaseModel):
    current_password: str = Field(min_length=1, max_length=128)
    new_password: str = Field(min_length=14, max_length=128)


class TrustRootOut(BaseModel):
    key_id: str
    algorithm: str
    public_key: str


class SessionAuthorizationOut(BaseModel):
    model_config = ConfigDict(json_encoders={datetime: lambda value: value.isoformat()})

    authorization_id: UUID
    protocol_version: str
    session_id: UUID
    course_offering_id: UUID
    faculty_id: UUID
    valid_from: datetime
    valid_until: datetime
    key_id: str
    session_public_key: str
    session_private_key: str | None = None
    server_signature: str


class FacultySessionOut(BaseModel):
    model_config = ConfigDict(json_encoders={datetime: lambda value: value.isoformat()})

    id: UUID
    course_offering_id: UUID
    course_code: str
    course_name: str
    section_code: str
    room: str | None
    scheduled_start: datetime
    scheduled_end: datetime
    started_at: datetime | None
    closed_at: datetime | None
    reconcile_until: datetime | None = None
    reconciliation_state: str | None = None
    state: str
    authorization: SessionAuthorizationOut | None


class StartSessionIn(BaseModel):
    course_offering_id: UUID


class RosterStudentOut(BaseModel):
    student_id: UUID
    roll_number: str
    display_name: str
    attendance_status: str | None
    attendance_method: str | None
    claim_state: str | None


class FacultyCourseOut(BaseModel):
    course_offering_id: UUID
    course_code: str
    course_name: str
    section_code: str
    student_count: int
    schedule_summary: str


class FacultySessionRecordOut(BaseModel):
    id: UUID
    course_offering_id: UUID
    course_code: str
    course_name: str
    section_code: str
    room: str | None
    scheduled_start: datetime
    scheduled_end: datetime
    state: str
    present: int
    absent: int
    expected: int


class FacultyRegisterSessionOut(BaseModel):
    id: UUID
    label: str
    scheduled_start: datetime
    state: str


class FacultyRegisterStudentOut(BaseModel):
    student_id: UUID
    roll_number: str
    display_name: str
    present: int
    absent: int
    percentage: float
    statuses: dict[str, str | None]


class FacultyRegisterOut(BaseModel):
    course_offering_id: UUID
    course_code: str
    course_name: str
    section_code: str
    sessions: list[FacultyRegisterSessionOut]
    students: list[FacultyRegisterStudentOut]


class FacultyAttestationIn(BaseModel):
    student_id: UUID
    reason: str = Field(min_length=3, max_length=120)

    @field_validator("reason")
    @classmethod
    def validate_reason(cls, value: str) -> str:
        allowed = {
            "Student device failure",
            "QR scanning failure",
            "Local connectivity failure",
            "Device registration problem",
            "System error",
            "Other approved reason",
        }
        normalized = value.strip()
        if normalized not in allowed:
            raise ValueError("Use an approved faculty attestation reason.")
        return normalized


class QrPayloadOut(BaseModel):
    protocol_version: str
    session_id: UUID
    epoch: int
    issued_at: datetime
    expires_at: datetime
    challenge: str
    key_id: str
    signature: str
    session_authorization: SessionAuthorizationOut


class AttendanceClaimIn(BaseModel):
    claim_id: UUID
    session_id: UUID
    student_id: UUID
    device_registration_id: UUID
    qr_epoch: int
    qr_challenge: str
    qr_issued_at: datetime
    qr_expires_at: datetime
    qr_signature: str
    qr_captured_at: datetime
    claim_created_at: datetime
    claim_expires_at: datetime
    device_signature: str


class AttendanceClaimOut(BaseModel):
    claim_id: UUID
    session_id: UUID
    claim_state: str
    claim_expires_at: datetime


class PresenceChallengeIn(BaseModel):
    challenge_id: UUID
    session_id: UUID
    claim_id: UUID
    presence_epoch: int
    nonce: str
    issued_at: datetime
    expires_at: datetime
    transport: str
    host_public_key: str


class PresenceResponseIn(BaseModel):
    response_id: UUID
    challenge_id: UUID
    session_id: UUID
    claim_id: UUID
    device_registration_id: UUID
    presence_epoch: int
    responded_at: datetime
    transport: str
    challenge_nonce: str
    host_public_key: str
    device_signature: str


class AttendanceProofIn(BaseModel):
    proof_id: UUID
    claim_id: UUID
    session_id: UUID
    student_id: UUID
    device_registration_id: UUID
    presence_challenge_id: UUID
    presence_response_id: UUID
    proof_created_at: datetime
    final_device_signature: str


class AttendanceProofSubmissionIn(BaseModel):
    protocol_version: str
    claim: AttendanceClaimIn
    challenge: PresenceChallengeIn
    response: PresenceResponseIn
    proof: AttendanceProofIn


class AttendanceProofResultOut(BaseModel):
    proof_id: UUID
    result: str
    attendance_record_id: UUID | None = None
    authoritative_status: str | None = None
    attendance_method: str | None = None
    recorded_at: datetime | None = None
    server_version: int | None = None
    error_code: str | None = None
    retryable: bool = False


class AttendanceProofBatchIn(BaseModel):
    proofs: list[AttendanceProofSubmissionIn]


class AttendanceProofBatchOut(BaseModel):
    results: list[AttendanceProofResultOut]
