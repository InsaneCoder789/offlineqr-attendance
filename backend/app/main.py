import logging
import secrets
import asyncio
import psycopg
from contextlib import asynccontextmanager
from time import perf_counter
from uuid import UUID

from fastapi import FastAPI, Request, Response, WebSocket
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
    prepare_today_attendance_sessions,
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
from .student_identity_service import authenticate_student, change_student_password, reset_student_password_by_roll
from .device_schemas import (
    AdminDecisionIn,
    AdminDeviceDetailOut,
    AdminDeviceHistoryOut,
    AdminDeviceStatsOut,
    AdminDeviceSummaryOut,
    AdminRevokeIn,
    DeviceActivationConsumeIn,
    DeviceActivationQrOut,
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
    consume_activation_qr,
    create_activation_qr,
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
from .redis_service import assert_available, faculty_session, publish_session_event, revoke_faculty_session, session_event_version, student_session
from .redis_service import create_faculty_session, create_student_session
from .oidc_service import verify_oidc_identity
from .security import RedisRateLimitMiddleware, SecurityHeadersMiddleware
from .schemas import (
    AttendanceRecordOut,
    AttendanceSummaryOut,
    BootstrapSyncOut,
    DevLoginIn,
    EnrollmentOut,
    StudentOut,
    StudentLoginIn,
    StudentLoginOut,
    OidcTokenIn,
    StudentPasswordChangeIn,
    StudentPasswordResetOut,
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
    allow_headers=["Authorization", "Content-Type", "X-CSRF-Token", "X-Correlation-Id"],
)
logger = logging.getLogger("offlineqr_attendance.sync")


def _require_development_identity() -> None:
    if not get_settings().development_enabled:
        raise ApiError("DEV_IDENTITY_DISABLED", "Development identity is disabled.", 403)


def _faculty_id_from_request(request: Request) -> UUID:
    token = request.cookies.get("offlineqr_faculty_session", "")
    if token:
        session = faculty_session(token)
        if session is None:
            raise ApiError("FACULTY_SESSION_EXPIRED", "Faculty session has expired. Sign in again.", 401)
        if request.method in {"POST", "PATCH", "PUT", "DELETE"}:
            supplied_csrf = request.headers.get("x-csrf-token", "")
            if not supplied_csrf or not secrets.compare_digest(supplied_csrf, session["csrf"]):
                raise ApiError("CSRF_VALIDATION_FAILED", "Request could not be verified.", 403)
        faculty_id = UUID(session["faculty_id"])
        try:
            faculty_profile(faculty_id)  # rejects deactivated accounts holding a live session
        except ApiError as exc:
            if exc.status_code == 404:
                raise ApiError("FACULTY_SESSION_EXPIRED", "Faculty session has expired. Sign in again.", 401) from exc
            raise
        return faculty_id
    if get_settings().development_enabled and request.headers.get("x-faculty-id"):
        identity = request.headers["x-faculty-id"]
        faculty = get_faculty_by_identity(identity)
        return faculty["id"]
    raise ApiError("FACULTY_AUTH_REQUIRED", "Faculty sign-in is required.", 401)


def _ict_admin_from_request(request: Request) -> tuple[UUID, dict]:
    faculty_id = _faculty_id_from_request(request)
    profile = faculty_profile(faculty_id)
    if profile["access_role"] != "ICT_ADMIN":
        raise ApiError("ICT_ADMIN_REQUIRED", "An ICT administrator session is required.", 403)
    return faculty_id, profile


def _websocket_origin_allowed(origin: str | None) -> bool:
    if not origin:
        return False
    if not settings.development_enabled:
        return origin in settings.cors_allowed_origins
    return origin.startswith(("http://localhost:", "http://127.0.0.1:", "http://10.", "http://192.168."))


def _student_id_from_request(request: Request) -> UUID:
    authorization = request.headers.get("authorization", "")
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() == "bearer" and token:
        session = student_session(token)
        if session is None:
            raise ApiError("STUDENT_SESSION_EXPIRED", "Student sign-in has expired. Sign in again.", 401)
        try:
            if session.get("must_change_password") is True and not request.url.path.endswith("/student/auth/password"):
                raise ApiError("STUDENT_PASSWORD_CHANGE_REQUIRED", "Change the temporary password before using attendance services.", 403)
            return UUID(session["student_id"])
        except (ValueError, KeyError) as exc:
            raise ApiError("STUDENT_SESSION_EXPIRED", "Student sign-in is invalid.", 401) from exc
    if get_settings().development_enabled and request.headers.get("x-student-id"):
        try:
            return UUID(request.headers["x-student-id"])
        except ValueError as exc:
            raise ApiError("STUDENT_AUTH_REQUIRED", "Student identity header is invalid.", 401) from exc
    raise ApiError("STUDENT_AUTH_REQUIRED", "Student sign-in is required.", 401)


@app.get("/api/v1/health")
def health() -> dict[str, str]:
    return readiness()


@app.get("/api/v1/health/live")
def liveness() -> dict[str, str]:
    return {"status": "alive"}


@app.get("/api/v1/health/ready")
def readiness() -> dict[str, str]:
    try:
        with psycopg.connect(settings.database_url, connect_timeout=2) as conn:
            conn.execute("SELECT 1").fetchone()
        assert_available()
    except Exception as exc:
        logger.error("readiness_check_failed", exc_info=exc)
        raise ApiError("SERVICE_NOT_READY", "A required service is unavailable.", 503) from exc
    return {"status": "ready"}


@app.get("/api/v1/me", response_model=StudentOut)
def me(request: Request) -> dict:
    return get_student(_student_id_from_request(request))


@app.post("/api/v1/auth/dev-login", response_model=BootstrapSyncOut)
def dev_login(payload: DevLoginIn) -> dict:
    _require_development_identity()
    student = get_student_by_email(payload.email)
    return bootstrap_student_sync(student["id"])


@app.post("/api/v1/student/auth/login", response_model=StudentLoginOut)
def student_login(payload: StudentLoginIn) -> dict:
    if not settings.password_auth_enabled:
        raise ApiError("PASSWORD_AUTH_DISABLED", "Use institutional sign-in.", 403)
    profile, token = authenticate_student(payload.roll_number, payload.password)
    return {**profile, "access_token": token, "expires_in": get_settings().student_session_ttl_seconds}


@app.post("/api/v1/student/auth/oidc", response_model=StudentLoginOut)
def student_oidc_login(payload: OidcTokenIn) -> dict:
    identity = verify_oidc_identity(payload.id_token)
    student = get_student_by_email(identity["email"])
    token = create_student_session(student["id"], must_change_password=False)
    return {
        **student,
        "access_token": token,
        "expires_in": settings.student_session_ttl_seconds,
        "must_change_password": False,
    }


@app.post("/api/v1/student/auth/password")
def student_change_password(payload: StudentPasswordChangeIn, request: Request) -> dict:
    change_student_password(_student_id_from_request(request), payload.current_password, payload.new_password)
    return {"result": "password_changed"}


@app.post("/api/v1/faculty/auth/login", response_model=FacultyLoginOut)
def faculty_login(payload: FacultyLoginIn, response: Response) -> dict:
    if not settings.password_auth_enabled:
        raise ApiError("PASSWORD_AUTH_DISABLED", "Use institutional sign-in.", 403)
    profile, token, csrf_token = authenticate_faculty(payload.email, payload.password)
    auth_settings = get_settings()
    response.set_cookie(
        "offlineqr_faculty_session",
        token,
        max_age=auth_settings.faculty_session_ttl_seconds,
        httponly=True,
        secure=auth_settings.faculty_cookie_secure,
        samesite="strict",
        path="/",
    )
    response.set_cookie(
        "offlineqr_faculty_csrf",
        csrf_token,
        max_age=auth_settings.faculty_session_ttl_seconds,
        httponly=False,
        secure=auth_settings.faculty_cookie_secure,
        samesite="strict",
        path="/",
    )
    return profile


@app.post("/api/v1/faculty/auth/oidc", response_model=FacultyLoginOut)
def faculty_oidc_login(payload: OidcTokenIn, response: Response) -> dict:
    identity = verify_oidc_identity(payload.id_token)
    faculty = get_faculty_by_identity(identity["email"])
    profile = faculty_profile(faculty["id"])
    token, csrf_token = create_faculty_session(faculty["id"])
    response.set_cookie(
        "offlineqr_faculty_session", token, max_age=settings.faculty_session_ttl_seconds,
        httponly=True, secure=settings.faculty_cookie_secure, samesite="strict", path="/",
    )
    response.set_cookie(
        "offlineqr_faculty_csrf", csrf_token, max_age=settings.faculty_session_ttl_seconds,
        httponly=False, secure=settings.faculty_cookie_secure, samesite="strict", path="/",
    )
    return profile


@app.post("/api/v1/faculty/auth/logout")
def faculty_logout(request: Request, response: Response) -> dict:
    token = request.cookies.get("offlineqr_faculty_session", "")
    revoke_faculty_session(token)  # expired sessions must still be able to clear their cookies
    response.delete_cookie("offlineqr_faculty_session", path="/")
    response.delete_cookie("offlineqr_faculty_csrf", path="/")
    return {"result": "signed_out"}


@app.get("/api/v1/faculty/profile", response_model=FacultyLoginOut)
def faculty_current_profile(request: Request) -> dict:
    return faculty_profile(_faculty_id_from_request(request))


@app.patch("/api/v1/faculty/profile", response_model=FacultyLoginOut)
def faculty_update_profile(payload: FacultyProfileUpdateIn, request: Request) -> dict:
    return update_faculty_profile(_faculty_id_from_request(request), payload.display_name, payload.phone_number)


@app.post("/api/v1/faculty/auth/password")
def faculty_change_password(
    payload: FacultyPasswordChangeIn,
    request: Request,
    response: Response,
) -> dict:
    change_faculty_password(_faculty_id_from_request(request), payload.current_password, payload.new_password)
    response.delete_cookie("offlineqr_faculty_session", path="/")
    response.delete_cookie("offlineqr_faculty_csrf", path="/")
    return {"result": "password_changed"}


@app.get("/api/v1/sync/bootstrap", response_model=BootstrapSyncOut)
def sync_bootstrap(request: Request) -> dict:
    student_id = _student_id_from_request(request)
    started = perf_counter()
    payload = bootstrap_student_sync(student_id)
    duration_ms = round((perf_counter() - started) * 1000, 2)
    logger.info(
        "bootstrap_sync",
        extra={
            "sync_version": payload["sync_version"],
            "student_id": str(student_id),
            "record_count": len(payload["attendance_records"]),
            "duration_ms": duration_ms,
            "result": "ok",
        },
    )
    return payload


@app.get("/api/v1/me/enrollments", response_model=list[EnrollmentOut])
def my_enrollments(request: Request) -> list[dict]:
    return bootstrap_student_sync(_student_id_from_request(request))["enrollments"]


@app.get("/api/v1/me/attendance", response_model=list[AttendanceRecordOut])
def my_attendance(request: Request) -> list[dict]:
    return bootstrap_student_sync(_student_id_from_request(request))["attendance_records"]


@app.get("/api/v1/me/attendance/summary", response_model=list[AttendanceSummaryOut])
def my_attendance_summary(request: Request) -> list[dict]:
    return bootstrap_student_sync(_student_id_from_request(request))["attendance_summaries"]


@app.get("/api/v1/trust-roots/current", response_model=TrustRootOut)
def current_trust_root() -> dict:
    return trust_root()


@app.get("/api/v1/me/timetable", response_model=list[TimetableEntryOut])
def my_timetable(request: Request) -> list[dict]:
    return student_timetable(_student_id_from_request(request))


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


@app.post(
    "/api/v1/faculty/attendance-sessions/offline-package",
    response_model=list[FacultySessionOut],
)
def faculty_offline_package(request: Request) -> list[dict]:
    """Prepare today's signed session credentials while the faculty is online."""
    return prepare_today_attendance_sessions(_faculty_id_from_request(request))


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
def faculty_session_qr(session_id: UUID, request: Request) -> dict:
    get_faculty_session(_faculty_id_from_request(request), session_id)
    return qr_payload_for(session_id)


@app.websocket("/api/v1/faculty/attendance-sessions/{session_id}/events")
async def faculty_session_events(websocket: WebSocket, session_id: UUID) -> None:
    """Authenticated Redis-backed session updates without browser polling the roster."""
    if not _websocket_origin_allowed(websocket.headers.get("origin")):
        await websocket.close(code=1008)
        return
    token = websocket.cookies.get("offlineqr_faculty_session", "")
    identity = faculty_session(token) if token else None
    if identity is None:
        await websocket.close(code=1008)
        return
    try:
        faculty_id = UUID(identity["faculty_id"])
        get_faculty_session(faculty_id, session_id)
    except (ApiError, ValueError):
        await websocket.close(code=1008)
        return
    await websocket.accept()
    version = -1
    try:
        while True:
            next_version = session_event_version(session_id)
            if next_version != version:
                version = next_version
                await websocket.send_json({"type": "SESSION_UPDATED", "session_id": str(session_id), "version": version})
            await asyncio.sleep(1)
    except Exception as exc:
        logger.debug("faculty_session_websocket_closed", extra={"session_id": str(session_id), "reason": type(exc).__name__})


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
        attestation_provider=payload.attestation_provider,
        attestation_token=payload.attestation_token,
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
        attestation_provider=payload.attestation_provider,
        attestation_token=payload.attestation_token,
    )


@app.get(
    "/api/v1/devices/replacement-requests/current",
    response_model=ReplacementRequestOut | None,
)
def device_replacement_current(request: Request) -> dict | None:
    return current_replacement_request(_student_id_from_request(request))


@app.post("/api/v1/devices/replacement-activation/consume", response_model=DeviceRegistrationOut)
def device_replacement_activation_consume(payload: DeviceActivationConsumeIn, request: Request) -> dict:
    return consume_activation_qr(student_id=_student_id_from_request(request), qr_payload=payload.qr_payload)


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


@app.post("/api/v1/admin/device-replacements/{request_id}/activation-qr", response_model=DeviceActivationQrOut)
def admin_replacement_activation_qr(request_id: UUID, request: Request) -> dict:
    _, profile = _ict_admin_from_request(request)
    return create_activation_qr(request_id=request_id, issued_by=profile["institutional_email"])


@app.post("/api/v1/admin/device-replacements/{request_id}/reject", response_model=ReplacementRequestOut)
def admin_replacement_reject(request_id: UUID, payload: AdminDecisionIn, request: Request) -> dict:
    _, profile = _ict_admin_from_request(request)
    return reject_replacement(request_id=request_id, rejected_by=profile["institutional_email"], decision_note=payload.note)


@app.post("/api/v1/admin/devices/{device_registration_id}/revoke")
def admin_device_revoke(device_registration_id: UUID, payload: AdminRevokeIn, request: Request) -> dict:
    _, profile = _ict_admin_from_request(request)
    return revoke_device(device_registration_id=device_registration_id, revoked_by=profile["institutional_email"], reason=payload.reason)


@app.post("/api/v1/admin/students/{roll_number}/password-reset", response_model=StudentPasswordResetOut)
def admin_student_password_reset(roll_number: str, request: Request) -> dict:
    _, profile = _ict_admin_from_request(request)
    temporary_password = reset_student_password_by_roll(roll_number, profile["institutional_email"])
    return {"temporary_password": temporary_password}
