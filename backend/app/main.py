import logging
from time import perf_counter
from uuid import UUID

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware

from .attendance_schemas import (
    AttendanceClaimIn,
    AttendanceClaimOut,
    AttendanceProofBatchIn,
    AttendanceProofBatchOut,
    AttendanceProofResultOut,
    AttendanceProofSubmissionIn,
    FacultyAttestationIn,
    FacultyClassOut,
    FacultyCourseOut,
    FacultyLoginIn,
    FacultyLoginOut,
    FacultyRegisterOut,
    FacultySessionOut,
    FacultySessionRecordOut,
    QrPayloadOut,
    RosterStudentOut,
    StartSessionIn,
    TimetableEntryOut,
    TrustRootOut,
)
from .attendance_service import (
    attest_student,
    close_attendance_session,
    faculty_courses,
    faculty_register,
    faculty_roster,
    finalize_reconciliation,
    faculty_session_history,
    get_faculty_session,
    qr_payload_for,
    start_attendance_session,
    student_timetable,
    submit_attendance_claim,
    submit_attendance_proof_batch,
    submit_attendance_proof_submission,
    today_faculty_classes,
    trust_root,
)
from .config import get_settings, validate_production_settings
from .device_schemas import (
    DeviceChallengeOut,
    DeviceRegistrationOut,
    DeviceVerificationOut,
    EnrollmentCompleteIn,
    ReplacementRequestIn,
    ReplacementRequestOut,
    VerificationChallengeIn,
    VerificationCompleteIn,
)
from .device_service import (
    approve_replacement,
    complete_enrollment,
    complete_verification,
    create_enrollment_challenge,
    create_replacement_challenge,
    create_verification_challenge,
    current_device,
    current_replacement_request,
    request_replacement,
)
from .errors import ApiError, api_error_handler
from .repositories import bootstrap_student_sync, get_faculty_by_identity, get_student, get_student_by_email
from .security import SecurityHeadersMiddleware, SlidingWindowRateLimitMiddleware, require_ict_approval
from .schemas import (
    AttendanceRecordOut,
    AttendanceSummaryOut,
    BootstrapSyncOut,
    DevLoginIn,
    EnrollmentOut,
    StudentOut,
)

app = FastAPI(title="KIIT Attendance Goal 02 API", version="0.2.0")
validate_production_settings()
app.add_exception_handler(ApiError, api_error_handler)
app.add_middleware(SecurityHeadersMiddleware)
app.add_middleware(SlidingWindowRateLimitMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:8080",
        "http://127.0.0.1:8080",
        "http://localhost:5173",
        "http://127.0.0.1:5173",
    ],
    allow_origin_regex=r"http://(localhost|127\.0\.0\.1|10\.\d+\.\d+\.\d+|192\.168\.\d+\.\d+):\d+",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
logger = logging.getLogger("kiit_attendance.sync")


def _require_development_identity() -> None:
    if not get_settings().development_enabled:
        raise ApiError("DEV_IDENTITY_DISABLED", "Development identity is disabled.", 403)


def _faculty_id_from_request(request: Request) -> UUID:
    _require_development_identity()
    identity = request.headers.get("x-faculty-id") or get_settings().dev_faculty_id
    faculty = get_faculty_by_identity(identity)
    return faculty["id"]


def _student_id_from_request(request: Request) -> UUID:
    _require_development_identity()
    return UUID(request.headers.get("x-student-id") or get_settings().dev_student_id)


@app.get("/api/v1/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/api/v1/me", response_model=StudentOut)
def me() -> dict:
    settings = get_settings()
    _require_development_identity()
    return get_student(UUID(settings.dev_student_id))


@app.post("/api/v1/auth/dev-login", response_model=BootstrapSyncOut)
def dev_login(payload: DevLoginIn) -> dict:
    _require_development_identity()
    student = get_student_by_email(payload.email)
    return bootstrap_student_sync(student["id"])


@app.post("/api/v1/faculty/auth/login", response_model=FacultyLoginOut)
def faculty_login(payload: FacultyLoginIn) -> dict:
    _require_development_identity()
    if payload.password != "admin":
        raise ApiError("INVALID_FACULTY_PASSWORD", "Invalid faculty password.", 401)
    normalized_email = payload.email.strip().lower()
    if not normalized_email.endswith("@kiit.ac.in"):
        raise ApiError("INVALID_KIIT_EMAIL", "Use your KIIT faculty email address.", 400)
    return get_faculty_by_identity(normalized_email)


@app.get("/api/v1/sync/bootstrap", response_model=BootstrapSyncOut)
def sync_bootstrap(request: Request) -> dict:
    settings = get_settings()
    _require_development_identity()
    student_id = request.headers.get("x-student-id") or settings.dev_student_id
    started = perf_counter()
    payload = bootstrap_student_sync(UUID(student_id))
    duration_ms = round((perf_counter() - started) * 1000, 2)
    logger.info(
        "bootstrap_sync",
        extra={
            "sync_version": payload["sync_version"],
            "student_id": student_id,
            "record_count": len(payload["attendance_records"]),
            "duration_ms": duration_ms,
            "result": "ok",
        },
    )
    return payload


@app.get("/api/v1/me/enrollments", response_model=list[EnrollmentOut])
def my_enrollments() -> list[dict]:
    settings = get_settings()
    _require_development_identity()
    return bootstrap_student_sync(UUID(settings.dev_student_id))["enrollments"]


@app.get("/api/v1/me/attendance", response_model=list[AttendanceRecordOut])
def my_attendance() -> list[dict]:
    settings = get_settings()
    _require_development_identity()
    return bootstrap_student_sync(UUID(settings.dev_student_id))["attendance_records"]


@app.get("/api/v1/me/attendance/summary", response_model=list[AttendanceSummaryOut])
def my_attendance_summary() -> list[dict]:
    settings = get_settings()
    _require_development_identity()
    return bootstrap_student_sync(UUID(settings.dev_student_id))["attendance_summaries"]


@app.get("/api/v1/trust-roots/current", response_model=TrustRootOut)
def current_trust_root() -> dict:
    return trust_root()


@app.get("/api/v1/me/timetable", response_model=list[TimetableEntryOut])
def my_timetable() -> list[dict]:
    settings = get_settings()
    _require_development_identity()
    return student_timetable(UUID(settings.dev_student_id))


@app.get("/api/v1/faculty/classes/today", response_model=list[FacultyClassOut])
def faculty_today(request: Request) -> list[dict]:
    return today_faculty_classes(_faculty_id_from_request(request))


@app.get("/api/v1/faculty/courses", response_model=list[FacultyCourseOut])
def faculty_course_list(request: Request) -> list[dict]:
    return faculty_courses(_faculty_id_from_request(request))


@app.get("/api/v1/faculty/attendance-sessions", response_model=list[FacultySessionRecordOut])
def faculty_sessions(request: Request, limit: int = 50) -> list[dict]:
    return faculty_session_history(_faculty_id_from_request(request), limit=limit)


@app.get("/api/v1/faculty/course-offerings/{course_offering_id}/register", response_model=FacultyRegisterOut)
def faculty_course_register(course_offering_id: UUID, request: Request) -> dict:
    return faculty_register(_faculty_id_from_request(request), course_offering_id)


@app.post("/api/v1/faculty/attendance-sessions/start", response_model=FacultySessionOut)
def faculty_start_session(payload: StartSessionIn, request: Request) -> dict:
    return start_attendance_session(_faculty_id_from_request(request), payload.course_offering_id)


@app.get("/api/v1/faculty/attendance-sessions/{session_id}", response_model=FacultySessionOut)
def faculty_get_session(session_id: UUID, request: Request) -> dict:
    return get_faculty_session(_faculty_id_from_request(request), session_id)


@app.post("/api/v1/faculty/attendance-sessions/{session_id}/close", response_model=FacultySessionOut)
def faculty_close_session(session_id: UUID, request: Request) -> dict:
    return close_attendance_session(_faculty_id_from_request(request), session_id)


@app.post("/api/v1/faculty/attendance-sessions/{session_id}/reconcile", response_model=FacultySessionOut)
def faculty_reconcile_session(session_id: UUID, request: Request) -> dict:
    return finalize_reconciliation(_faculty_id_from_request(request), session_id)


@app.get("/api/v1/faculty/attendance-sessions/{session_id}/roster", response_model=list[RosterStudentOut])
def faculty_session_roster(session_id: UUID, request: Request) -> list[dict]:
    return faculty_roster(_faculty_id_from_request(request), session_id)


@app.post("/api/v1/faculty/attendance-sessions/{session_id}/attest")
def faculty_attest(session_id: UUID, payload: FacultyAttestationIn, request: Request) -> dict:
    return attest_student(_faculty_id_from_request(request), session_id, payload.student_id, payload.reason)


@app.get("/api/v1/faculty/attendance-sessions/{session_id}/qr", response_model=QrPayloadOut)
def faculty_session_qr(session_id: UUID) -> dict:
    return qr_payload_for(session_id)


@app.post("/api/v1/attendance-claims", response_model=AttendanceClaimOut)
def attendance_claim(payload: AttendanceClaimIn) -> dict:
    return submit_attendance_claim(payload.model_dump())


@app.post("/api/v1/attendance/proofs", response_model=AttendanceProofResultOut)
def attendance_proof(payload: AttendanceProofSubmissionIn) -> dict:
    return submit_attendance_proof_submission(payload.model_dump())


@app.post("/api/v1/attendance/proofs/batch", response_model=AttendanceProofBatchOut)
def attendance_proof_batch(payload: AttendanceProofBatchIn) -> dict:
    return {"results": submit_attendance_proof_batch([item.model_dump() for item in payload.proofs])}


@app.post(
    "/api/v1/devices/enrollment/challenge",
    response_model=DeviceChallengeOut,
)
def device_enrollment_challenge(request: Request) -> dict:
    return create_enrollment_challenge(_student_id_from_request(request))


@app.post(
    "/api/v1/devices/enrollment/complete",
    response_model=DeviceRegistrationOut,
)
def device_enrollment_complete(payload: EnrollmentCompleteIn, request: Request) -> dict:
    student_id = _student_id_from_request(request)
    return complete_enrollment(
        student_id=student_id,
        challenge_id=payload.challenge_id,
        public_key=payload.public_key,
        public_key_algorithm=payload.public_key_algorithm,
        signature=payload.signature,
        platform=payload.platform,
        display_label=payload.display_label,
        app_instance_metadata=payload.app_instance_metadata,
        key_protection=payload.key_protection,
    )


@app.get("/api/v1/devices/current", response_model=DeviceRegistrationOut | None)
def devices_current(request: Request) -> dict | None:
    return current_device(_student_id_from_request(request))


@app.post(
    "/api/v1/devices/verification/challenge",
    response_model=DeviceChallengeOut,
)
def device_verification_challenge(payload: VerificationChallengeIn, request: Request) -> dict:
    return create_verification_challenge(
        student_id=_student_id_from_request(request),
        device_registration_id=payload.device_registration_id,
    )


@app.post(
    "/api/v1/devices/verification/complete",
    response_model=DeviceVerificationOut,
)
def device_verification_complete(payload: VerificationCompleteIn, request: Request) -> dict:
    return complete_verification(
        student_id=_student_id_from_request(request),
        challenge_id=payload.challenge_id,
        device_registration_id=payload.device_registration_id,
        signature=payload.signature,
    )


@app.post(
    "/api/v1/devices/replacement/challenge",
    response_model=DeviceChallengeOut,
)
def device_replacement_challenge(request: Request) -> dict:
    return create_replacement_challenge(_student_id_from_request(request))


@app.post(
    "/api/v1/devices/replacement-requests",
    response_model=ReplacementRequestOut,
)
def device_replacement_request(payload: ReplacementRequestIn, request: Request) -> dict:
    return request_replacement(
        student_id=_student_id_from_request(request),
        challenge_id=payload.challenge_id,
        public_key=payload.public_key,
        public_key_algorithm=payload.public_key_algorithm,
        signature=payload.signature,
        platform=payload.platform,
        reason=payload.reason,
        display_label=payload.display_label,
        app_instance_metadata=payload.app_instance_metadata,
        key_protection=payload.key_protection,
    )


@app.get(
    "/api/v1/devices/replacement-requests/current",
    response_model=ReplacementRequestOut | None,
)
def device_replacement_current(request: Request) -> dict | None:
    return current_replacement_request(_student_id_from_request(request))


@app.post(
    "/api/v1/devices/replacement-requests/{request_id}/approve",
    response_model=ReplacementRequestOut,
)
def device_replacement_approve(request_id: UUID, request: Request) -> dict:
    require_ict_approval(request)
    approver = request.headers.get("x-ict-operator", "ict-admin")
    return approve_replacement(request_id=request_id, approved_by=approver)
