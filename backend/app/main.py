import logging
import secrets
from contextlib import asynccontextmanager
from time import perf_counter
from uuid import UUID

from fastapi import FastAPI, Request, Response
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
    FacultyPasswordChangeIn,
    FacultyProfileUpdateIn,
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
from .faculty_identity_service import (
    authenticate_faculty,
    change_faculty_password,
    faculty_profile,
    update_faculty_profile,
)
from .device_schemas import (
    AdminDecisionIn,
    AdminDeviceDetailOut,
    AdminDeviceHistoryOut,
    AdminDeviceStatsOut,
    AdminDeviceSummaryOut,
    AdminRevokeIn,
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
    reject_replacement,
    revoke_device,
)
from .admin_service import (
    admin_device_detail,
    admin_device_history,
    admin_device_stats,
    admin_devices,
    admin_pending_replacements,
)
from .errors import ApiError, api_error_handler
from .repositories import bootstrap_student_sync, get_faculty_by_identity, get_student, get_student_by_email
from .redis_service import assert_available, faculty_session, publish_session_event, revoke_faculty_session
from .security import RedisRateLimitMiddleware, SecurityHeadersMiddleware
from .schemas import (
    AttendanceRecordOut,
    AttendanceSummaryOut,
    BootstrapSyncOut,
    DevLoginIn,
    EnrollmentOut,
    StudentOut,
)

@asynccontextmanager
async def lifespan(_: FastAPI):
    assert_available()
    yield


settings = get_settings()
app = FastAPI(title="Dynamic QR Offline Attendance API", version="0.5.0", lifespan=lifespan)
validate_production_settings()
app.add_exception_handler(ApiError, api_error_handler)
app.add_middleware(SecurityHeadersMiddleware)
app.add_middleware(RedisRateLimitMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=(settings.cors_allowed_origins if not settings.development_enabled else [
        "http://localhost:8080",
        "http://127.0.0.1:8080",
        "http://localhost:5173",
        "http://127.0.0.1:5173",
    ]),
    allow_origin_regex=(r"http://(localhost|127\.0\.0\.1|10\.\d+\.\d+\.\d+|192\.168\.\d+\.\d+):\d+" if settings.development_enabled else None),
    allow_credentials=True,
    allow_methods=["GET", "POST", "PATCH", "OPTIONS"],
    allow_headers=["Content-Type", "X-CSRF-Token", "X-Correlation-Id"],
)
logger = logging.getLogger("kiit_attendance.sync")


def _require_development_identity() -> None:
    if not get_settings().development_enabled:
        raise ApiError("DEV_IDENTITY_DISABLED", "Development identity is disabled.", 403)


def _faculty_id_from_request(request: Request) -> UUID:
    token = request.cookies.get("kiit_faculty_session", "")
    if token:
        session = faculty_session(token)
        if session is None:
            raise ApiError("FACULTY_SESSION_EXPIRED", "Faculty session has expired. Sign in again.", 401)
        if request.method in {"POST", "PATCH", "PUT", "DELETE"}:
            supplied_csrf = request.headers.get("x-csrf-token", "")
            if not supplied_csrf or not secrets.compare_digest(supplied_csrf, session["csrf"]):
                raise ApiError("CSRF_VALIDATION_FAILED", "Request could not be verified.", 403)
        return UUID(session["faculty_id"])
    if get_settings().development_enabled:
        identity = request.headers.get("x-faculty-id") or get_settings().dev_faculty_id
        faculty = get_faculty_by_identity(identity)
        return faculty["id"]
    raise ApiError("FACULTY_AUTH_REQUIRED", "Faculty sign-in is required.", 401)


def _ict_admin_from_request(request: Request) -> tuple[UUID, dict]:
    faculty_id = _faculty_id_from_request(request)
    profile = faculty_profile(faculty_id)
    if profile["access_role"] != "ICT_ADMIN":
        raise ApiError("ICT_ADMIN_REQUIRED", "An ICT administrator session is required.", 403)
    return faculty_id, profile


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
def faculty_login(payload: FacultyLoginIn, response: Response) -> dict:
    profile, token, csrf_token = authenticate_faculty(payload.email, payload.password)
    settings = get_settings()
    response.set_cookie(
        "kiit_faculty_session",
        token,
        max_age=settings.faculty_session_ttl_seconds,
        httponly=True,
        secure=settings.faculty_cookie_secure,
        samesite="strict",
        path="/",
    )
    response.set_cookie(
        "kiit_faculty_csrf",
        csrf_token,
        max_age=settings.faculty_session_ttl_seconds,
        httponly=False,
        secure=settings.faculty_cookie_secure,
        samesite="strict",
        path="/",
    )
    return profile


@app.post("/api/v1/faculty/auth/logout")
def faculty_logout(request: Request, response: Response) -> dict:
    token = request.cookies.get("kiit_faculty_session", "")
    if token:
        _faculty_id_from_request(request)
    revoke_faculty_session(token)
    response.delete_cookie("kiit_faculty_session", path="/")
    response.delete_cookie("kiit_faculty_csrf", path="/")
    return {"result": "signed_out"}


@app.get("/api/v1/faculty/profile", response_model=FacultyLoginOut)
def faculty_current_profile(request: Request) -> dict:
    return faculty_profile(_faculty_id_from_request(request))


@app.patch("/api/v1/faculty/profile", response_model=FacultyLoginOut)
def faculty_update_profile(payload: FacultyProfileUpdateIn, request: Request) -> dict:
    return update_faculty_profile(_faculty_id_from_request(request), payload.display_name, payload.phone_number)


@app.post("/api/v1/faculty/auth/password")
def faculty_change_password(payload: FacultyPasswordChangeIn, request: Request) -> dict:
    change_faculty_password(_faculty_id_from_request(request), payload.current_password, payload.new_password)
    return {"result": "password_changed"}


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
    session = start_attendance_session(_faculty_id_from_request(request), payload.course_offering_id)
    _notify_session_change(session["id"], "SESSION_STARTED")
    return session


@app.get("/api/v1/faculty/attendance-sessions/{session_id}", response_model=FacultySessionOut)
def faculty_get_session(session_id: UUID, request: Request) -> dict:
    return get_faculty_session(_faculty_id_from_request(request), session_id)


@app.post("/api/v1/faculty/attendance-sessions/{session_id}/close", response_model=FacultySessionOut)
def faculty_close_session(session_id: UUID, request: Request) -> dict:
    session = close_attendance_session(_faculty_id_from_request(request), session_id)
    _notify_session_change(session_id, "SESSION_CLOSED")
    return session


@app.post("/api/v1/faculty/attendance-sessions/{session_id}/reconcile", response_model=FacultySessionOut)
def faculty_reconcile_session(session_id: UUID, request: Request) -> dict:
    session = finalize_reconciliation(_faculty_id_from_request(request), session_id)
    _notify_session_change(session_id, "SESSION_RECONCILED")
    return session


@app.get("/api/v1/faculty/attendance-sessions/{session_id}/roster", response_model=list[RosterStudentOut])
def faculty_session_roster(session_id: UUID, request: Request) -> list[dict]:
    return faculty_roster(_faculty_id_from_request(request), session_id)


@app.post("/api/v1/faculty/attendance-sessions/{session_id}/attest")
def faculty_attest(session_id: UUID, payload: FacultyAttestationIn, request: Request) -> dict:
    record = attest_student(_faculty_id_from_request(request), session_id, payload.student_id, payload.reason)
    _notify_session_change(session_id, "FACULTY_ATTESTATION")
    return record


@app.get("/api/v1/faculty/attendance-sessions/{session_id}/qr", response_model=QrPayloadOut)
def faculty_session_qr(session_id: UUID) -> dict:
    return qr_payload_for(session_id)


@app.post("/api/v1/attendance-claims", response_model=AttendanceClaimOut)
def attendance_claim(payload: AttendanceClaimIn) -> dict:
    return submit_attendance_claim(payload.model_dump())


@app.post("/api/v1/attendance/proofs", response_model=AttendanceProofResultOut)
def attendance_proof(payload: AttendanceProofSubmissionIn) -> dict:
    result = submit_attendance_proof_submission(payload.model_dump())
    if result["result"] in {"ACCEPTED", "ALREADY_ACCEPTED"}:
        _notify_session_change(payload.proof.session_id, "ATTENDANCE_PROOF_ACCEPTED")
    return result


@app.post("/api/v1/attendance/proofs/batch", response_model=AttendanceProofBatchOut)
def attendance_proof_batch(payload: AttendanceProofBatchIn) -> dict:
    results = submit_attendance_proof_batch([item.model_dump() for item in payload.proofs])
    for item, result in zip(payload.proofs, results, strict=True):
        if result["result"] in {"ACCEPTED", "ALREADY_ACCEPTED"}:
            _notify_session_change(item.proof.session_id, "ATTENDANCE_PROOF_ACCEPTED")
    return {"results": results}


def _notify_session_change(session_id: UUID, event_type: str) -> None:
    try:
        publish_session_event(session_id, event_type)
    except ApiError:
        # PostgreSQL is authoritative. A transient notification failure must not
        # hide an already committed attendance decision from the caller.
        logger.warning("session_coordination_event_unavailable", extra={"session_id": str(session_id), "event": event_type})


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
        device_profile=payload.device_profile.model_dump(),
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
        device_profile=payload.device_profile.model_dump(),
        key_protection=payload.key_protection,
    )


@app.get(
    "/api/v1/devices/replacement-requests/current",
    response_model=ReplacementRequestOut | None,
)
def device_replacement_current(request: Request) -> dict | None:
    return current_replacement_request(_student_id_from_request(request))


@app.get("/api/v1/admin/device-stats", response_model=AdminDeviceStatsOut)
def admin_device_statistics(request: Request) -> dict:
    _ict_admin_from_request(request)
    return admin_device_stats()


@app.get("/api/v1/admin/devices", response_model=list[AdminDeviceSummaryOut])
def admin_device_list(request: Request, query: str | None = None, status: str | None = None) -> list[dict]:
    _ict_admin_from_request(request)
    return admin_devices(query=query, status=status)


@app.get("/api/v1/admin/devices/{device_registration_id}", response_model=AdminDeviceDetailOut)
def admin_device_get(device_registration_id: UUID, request: Request) -> dict:
    _ict_admin_from_request(request)
    return admin_device_detail(device_registration_id)


@app.get("/api/v1/admin/devices/{device_registration_id}/history", response_model=list[AdminDeviceHistoryOut])
def admin_device_audit_history(device_registration_id: UUID, request: Request) -> list[dict]:
    _ict_admin_from_request(request)
    return admin_device_history(device_registration_id)


@app.get("/api/v1/admin/device-replacements")
def admin_replacement_list(request: Request) -> list[dict]:
    _ict_admin_from_request(request)
    return admin_pending_replacements()


@app.post("/api/v1/admin/device-replacements/{request_id}/approve", response_model=ReplacementRequestOut)
def admin_replacement_approve(request_id: UUID, payload: AdminDecisionIn, request: Request) -> dict:
    _, profile = _ict_admin_from_request(request)
    return approve_replacement(request_id=request_id, approved_by=profile["institutional_email"], decision_note=payload.note)


@app.post("/api/v1/admin/device-replacements/{request_id}/reject", response_model=ReplacementRequestOut)
def admin_replacement_reject(request_id: UUID, payload: AdminDecisionIn, request: Request) -> dict:
    _, profile = _ict_admin_from_request(request)
    return reject_replacement(request_id=request_id, rejected_by=profile["institutional_email"], decision_note=payload.note)


@app.post("/api/v1/admin/devices/{device_registration_id}/revoke")
def admin_device_revoke(device_registration_id: UUID, payload: AdminRevokeIn, request: Request) -> dict:
    _, profile = _ict_admin_from_request(request)
    return revoke_device(device_registration_id=device_registration_id, revoked_by=profile["institutional_email"], reason=payload.reason)
