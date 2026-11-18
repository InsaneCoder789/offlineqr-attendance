from __future__ import annotations

from datetime import UTC, date, datetime, time, timedelta
from uuid import UUID
import secrets

import psycopg
import psycopg.errors
from psycopg.rows import dict_row
from nacl.signing import SigningKey

from .attendance_protocol import (
    ATTENDANCE_QR_PROTOCOL,
    CLOCK_SKEW_SECONDS,
    QR_EPOCH_SECONDS,
    SESSION_AUTHORIZATION_MAX_SECONDS,
    SESSION_AUTHORIZATION_PROTOCOL,
    canonical_attendance_claim,
    canonical_attendance_qr,
    canonical_session_authorization,
    epoch_for,
    epoch_window,
    institution_public_key,
    institution_key_id,
    institution_signing_key,
    javascript_date_precision,
    sign,
    verify,
)
from .config import get_settings
from .db import connect
from .device_crypto import verify_signature
from .errors import ApiError
from .institution_clock import institution_local_to_utc, institution_today
from .presence_protocol import (
    ATTENDANCE_PROOF_PROTOCOL,
    canonical_attendance_proof,
    canonical_presence_response,
)


def _connect():
    return connect()


def today_faculty_classes(faculty_id: UUID, today: date | None = None) -> list[dict]:
    current = today or institution_today()
    day = current.isoweekday()
    with _connect() as conn:
        rows = conn.execute(
            """
            SELECT co.id AS course_offering_id, c.code AS course_code, c.name AS course_name,
                   sec.code AS section_code, te.room, te.start_time::text, te.end_time::text,
                   EXISTS (
                       SELECT 1 FROM session_authorizations sa
                       JOIN attendance_sessions sess ON sess.id = sa.attendance_session_id
                       WHERE sa.faculty_id = fa.faculty_id
                         AND sa.course_offering_id = co.id
                         AND sess.state != 'CANCELLED'
                         AND sa.valid_until > now()
                   ) AS offline_ready
            FROM faculty_assignments fa
            JOIN course_offerings co ON co.id = fa.course_offering_id
            JOIN courses c ON c.id = co.course_id
            JOIN sections sec ON sec.id = co.section_id
            JOIN timetable_entries te ON te.course_offering_id = co.id
            WHERE fa.faculty_id = %s AND fa.active = true
              AND te.day_of_week = %s
              AND te.valid_from <= %s AND te.valid_until >= %s
            ORDER BY te.start_time, c.code
            """,
            [faculty_id, day, current, current],
        ).fetchall()
        return [dict(row) for row in rows]


def student_timetable(student_id: UUID, today: date | None = None) -> list[dict]:
    current = today or institution_today()
    day = current.isoweekday()
    with _connect() as conn:
        rows = conn.execute(
            """
            SELECT te.id, te.course_offering_id, te.day_of_week, te.start_time::text,
                   te.end_time::text, te.room, te.valid_from::text, te.valid_until::text
            FROM timetable_entries te
            JOIN enrollments e ON e.course_offering_id = te.course_offering_id
            WHERE e.student_id = %s AND e.active = true
              AND te.day_of_week = %s
              AND te.valid_from <= %s AND te.valid_until >= %s
            ORDER BY te.start_time, te.id
            """,
            [student_id, day, current, current],
        ).fetchall()
        return [dict(row) for row in rows]


def prepare_attendance_session(faculty_id: UUID, course_offering_id: UUID) -> dict:
    """Pre-authorize a scheduled class so its QR can be hosted without internet."""
    now = datetime.now(UTC)
    current = institution_today(now)
    day = current.isoweekday()
    with _connect() as conn:
        with conn.transaction():
            _require_faculty_offering(conn, faculty_id, course_offering_id)
            entry = conn.execute(
                """
                SELECT start_time, end_time, room
                FROM timetable_entries
                WHERE course_offering_id = %s AND day_of_week = %s
                  AND valid_from <= %s AND valid_until >= %s AND active = true
                ORDER BY start_time
                LIMIT 1
                """,
                [course_offering_id, day, current, current],
            ).fetchone()
            if entry is None:
                raise ApiError("TIMETABLE_ENTRY_NOT_FOUND", "No class is scheduled today.", 404)

            scheduled_start = institution_local_to_utc(current, entry["start_time"])
            scheduled_end = institution_local_to_utc(current, entry["end_time"])
            existing = conn.execute(
                """
                SELECT id FROM attendance_sessions
                WHERE course_offering_id = %s AND scheduled_start = %s
                  AND state IN ('CREATED', 'ACTIVE', 'SYNCING')
                ORDER BY created_at DESC LIMIT 1
                """,
                [course_offering_id, scheduled_start],
            ).fetchone()
            if existing is None:
                existing = conn.execute(
                    """
                    INSERT INTO attendance_sessions (
                        course_offering_id, created_by_faculty_id, scheduled_start,
                        scheduled_end, started_at, state
                    )
                    VALUES (%s, %s, %s, %s, %s, 'CREATED')
                    RETURNING id
                    """,
                    [course_offering_id, faculty_id, scheduled_start, scheduled_end, now],
                ).fetchone()
                _snapshot_roster(conn, existing["id"])
                _audit(
                    conn,
                    "ATTENDANCE_SESSION_PREPARED",
                    "attendance_session",
                    existing["id"],
                    str(faculty_id),
                )
            session_id = existing["id"]
            authorization = _ensure_authorization(
                conn,
                session_id,
                faculty_id,
                course_offering_id,
                scheduled_start,
                scheduled_end,
            )
            session = _session_by_id(conn, session_id)
            session["authorization"] = authorization
            return session


def prepare_today_attendance_sessions(faculty_id: UUID) -> list[dict]:
    prepared = []
    for item in today_faculty_classes(faculty_id):
        prepared.append(
            prepare_attendance_session(faculty_id, item["course_offering_id"])
        )
    return prepared


def start_attendance_session(faculty_id: UUID, course_offering_id: UUID) -> dict:
    now = datetime.now(UTC)
    current = institution_today(now)
    day = current.isoweekday()
    with _connect() as conn:
        with conn.transaction():
            assignment = conn.execute(
                """
                SELECT 1 FROM faculty_assignments
                WHERE faculty_id = %s AND course_offering_id = %s AND active = true
                """,
                [faculty_id, course_offering_id],
            ).fetchone()
            if assignment is None:
                raise ApiError("FACULTY_NOT_AUTHORIZED", "Faculty cannot start this class.", 403)

            entry = conn.execute(
                """
                SELECT start_time, end_time, room
                FROM timetable_entries
                WHERE course_offering_id = %s AND day_of_week = %s
                  AND valid_from <= %s AND valid_until >= %s AND active = true
                ORDER BY start_time
                LIMIT 1
                """,
                [course_offering_id, day, current, current],
            ).fetchone()
            if entry is None:
                raise ApiError("TIMETABLE_ENTRY_NOT_FOUND", "No class is scheduled today.", 404)

            scheduled_start = institution_local_to_utc(current, entry["start_time"])
            scheduled_end = institution_local_to_utc(current, entry["end_time"])
            existing = conn.execute(
                """
                SELECT id, state::text AS state FROM attendance_sessions
                WHERE course_offering_id = %s
                  AND scheduled_start = %s
                  AND state IN ('CREATED', 'ACTIVE', 'SYNCING')
                ORDER BY created_at DESC LIMIT 1
                """,
                [course_offering_id, scheduled_start],
            ).fetchone()
            if existing is None:
                created = conn.execute(
                    """
                    INSERT INTO attendance_sessions (
                        course_offering_id, created_by_faculty_id, scheduled_start,
                        scheduled_end, started_at, state
                    )
                    VALUES (%s, %s, %s, %s, %s, 'ACTIVE')
                    ON CONFLICT DO NOTHING
                    RETURNING id
                    """,
                    [course_offering_id, faculty_id, scheduled_start, scheduled_end, now],
                ).fetchone()
                if created is not None:
                    session_id = created["id"]
                    _snapshot_roster(conn, session_id)
                else:
                    existing = conn.execute(
                        """
                        SELECT id, state::text AS state FROM attendance_sessions
                        WHERE course_offering_id = %s AND scheduled_start = %s
                          AND state IN ('CREATED', 'ACTIVE', 'SYNCING')
                        ORDER BY created_at DESC LIMIT 1
                        """,
                        [course_offering_id, scheduled_start],
                    ).fetchone()
                    if existing is None:
                        raise ApiError("SESSION_START_CONFLICT", "Attendance session start conflicted. Retry once.", 409)
                    session_id = existing["id"]
            else:
                session_id = existing["id"]
            if existing is not None:
                conn.execute(
                    """
                    UPDATE attendance_sessions
                    SET state = 'ACTIVE', started_at = COALESCE(started_at, %s), updated_at = now()
                    WHERE id = %s
                    """,
                    [now, session_id],
                )
                _snapshot_roster(conn, session_id)

            authorization = _ensure_authorization(conn, session_id, faculty_id, course_offering_id, scheduled_start, scheduled_end)
            _audit(conn, "ATTENDANCE_SESSION_STARTED", "attendance_session", session_id, str(faculty_id))
            session = _session_by_id(conn, session_id)
            session["authorization"] = authorization
            return session


def get_faculty_session(faculty_id: UUID, session_id: UUID) -> dict:
    with _connect() as conn:
        session = _session_by_id(conn, session_id)
        if str(session["created_by_faculty_id"]) != str(faculty_id):
            raise ApiError("FACULTY_NOT_AUTHORIZED", "Faculty cannot view this session.", 403)
        session["authorization"] = _authorization_for_session(conn, session_id, include_private=True)
        return session


def close_attendance_session(faculty_id: UUID, session_id: UUID) -> dict:
    with _connect() as conn:
        with conn.transaction():
            session = _session_by_id(conn, session_id)
            if str(session["created_by_faculty_id"]) != str(faculty_id):
                raise ApiError("FACULTY_NOT_AUTHORIZED", "Faculty cannot close this session.", 403)
            conn.execute(
                """
                UPDATE attendance_sessions
                SET state = 'SYNCING', closed_at = now(),
                    reconcile_until = now() + interval '7 days',
                    reconciliation_state = 'PENDING', updated_at = now()
                WHERE id = %s AND state = 'ACTIVE'
                """,
                [session_id],
            )
            _audit(conn, "ATTENDANCE_SESSION_CLOSED", "attendance_session", session_id, str(faculty_id))
            session = _session_by_id(conn, session_id)
            session["authorization"] = _authorization_for_session(conn, session_id, include_private=True)
            return session


def finalize_reconciliation(faculty_id: UUID, session_id: UUID) -> dict:
    """Seal a closed session after its offline-proof reconciliation window."""
    with _connect() as conn:
        with conn.transaction():
            session = _session_by_id(conn, session_id)
            if str(session["created_by_faculty_id"]) != str(faculty_id):
                raise ApiError("FACULTY_NOT_AUTHORIZED", "Faculty cannot finalize this session.", 403)
            if session["state"] != "SYNCING":
                raise ApiError("SESSION_NOT_SYNCING", "Session is not waiting for reconciliation.", 409)
            if session["reconcile_until"] is None or datetime.now(UTC) < _aware(session["reconcile_until"]):
                raise ApiError("RECONCILIATION_WINDOW_OPEN", "Offline-proof reconciliation is still open.", 409)
            conn.execute(
                """
                UPDATE attendance_sessions
                SET state = 'RECONCILED', reconciliation_state = 'RECONCILED', updated_at = now()
                WHERE id = %s AND state = 'SYNCING'
                """,
                [session_id],
            )
            # Rostered students with no verified record are definitively absent once the window closes.
            conn.execute(
                """
                INSERT INTO attendance_records (attendance_session_id, student_id, status, method, recorded_at)
                SELECT r.attendance_session_id, r.student_id, 'ABSENT', NULL, now()
                FROM attendance_session_roster r
                WHERE r.attendance_session_id = %s
                ON CONFLICT (attendance_session_id, student_id) DO NOTHING
                """,
                [session_id],
            )
            _audit(conn, "ATTENDANCE_SESSION_RECONCILED", "attendance_session", session_id, str(faculty_id))
            session = _session_by_id(conn, session_id)
            session["authorization"] = _authorization_for_session(conn, session_id, include_private=True)
            return session


def faculty_roster(faculty_id: UUID, session_id: UUID) -> list[dict]:
    with _connect() as conn:
        session = _session_by_id(conn, session_id)
        if str(session["created_by_faculty_id"]) != str(faculty_id):
            raise ApiError("FACULTY_NOT_AUTHORIZED", "Faculty cannot view this roster.", 403)
        rows = conn.execute(
            """
            SELECT r.student_id, r.roll_number_snapshot AS roll_number,
                   r.student_name_snapshot AS display_name,
                   ar.status::text AS attendance_status,
                   ar.method::text AS attendance_method,
                   ac.claim_state::text AS claim_state
            FROM attendance_session_roster r
            LEFT JOIN attendance_records ar
              ON ar.attendance_session_id = r.attendance_session_id
             AND ar.student_id = r.student_id
            LEFT JOIN attendance_claims ac
              ON ac.attendance_session_id = r.attendance_session_id
             AND ac.student_id = r.student_id
            WHERE r.attendance_session_id = %s
            ORDER BY r.roll_number_snapshot
            """,
            [session_id],
        ).fetchall()
        return [dict(row) for row in rows]


def faculty_courses(faculty_id: UUID) -> list[dict]:
    with _connect() as conn:
        rows = conn.execute(
            """
            SELECT co.id AS course_offering_id, c.code AS course_code,
                   c.name AS course_name, sec.code AS section_code,
                   COUNT(DISTINCT e.student_id)::int AS student_count,
                   COALESCE(
                     string_agg(
                       DISTINCT concat(
                         CASE te.day_of_week
                           WHEN 1 THEN 'Mon'
                           WHEN 2 THEN 'Tue'
                           WHEN 3 THEN 'Wed'
                           WHEN 4 THEN 'Thu'
                           WHEN 5 THEN 'Fri'
                           WHEN 6 THEN 'Sat'
                           ELSE 'Sun'
                         END,
                         ' ',
                         to_char(te.start_time, 'HH24:MI'),
                         '-',
                         to_char(te.end_time, 'HH24:MI')
                       ),
                       ', '
                     ),
                     'No active timetable'
                   ) AS schedule_summary
            FROM faculty_assignments fa
            JOIN course_offerings co ON co.id = fa.course_offering_id
            JOIN courses c ON c.id = co.course_id
            JOIN sections sec ON sec.id = co.section_id
            LEFT JOIN enrollments e ON e.course_offering_id = co.id AND e.active = true
            LEFT JOIN timetable_entries te ON te.course_offering_id = co.id AND te.active = true
            WHERE fa.faculty_id = %s AND fa.active = true
            GROUP BY co.id, c.code, c.name, sec.code
            ORDER BY sec.code, c.code
            """,
            [faculty_id],
        ).fetchall()
        return [dict(row) for row in rows]


def faculty_session_history(faculty_id: UUID, limit: int = 50) -> list[dict]:
    bounded_limit = max(1, min(limit, 100))
    with _connect() as conn:
        rows = conn.execute(
            """
            SELECT sess.id, sess.course_offering_id, c.code AS course_code,
                   c.name AS course_name, sec.code AS section_code,
                   te.room, sess.scheduled_start, sess.scheduled_end,
                   sess.state::text AS state,
                   COUNT(DISTINCT r.student_id)::int AS expected,
                   COUNT(DISTINCT ar.id) FILTER (WHERE ar.status = 'PRESENT')::int AS present,
                   COUNT(DISTINCT ar.id) FILTER (WHERE ar.status = 'ABSENT')::int AS absent
            FROM attendance_sessions sess
            JOIN faculty_assignments fa
              ON fa.course_offering_id = sess.course_offering_id
             AND fa.faculty_id = %s
             AND fa.active = true
            JOIN course_offerings co ON co.id = sess.course_offering_id
            JOIN courses c ON c.id = co.course_id
            JOIN sections sec ON sec.id = co.section_id
            LEFT JOIN timetable_entries te
              ON te.course_offering_id = sess.course_offering_id
             AND te.day_of_week = EXTRACT(ISODOW FROM sess.scheduled_start)::int
             AND te.start_time = sess.scheduled_start::time
             AND te.active = true
            LEFT JOIN attendance_session_roster r ON r.attendance_session_id = sess.id
            LEFT JOIN attendance_records ar ON ar.attendance_session_id = sess.id
            GROUP BY sess.id, c.code, c.name, sec.code, te.room
            ORDER BY sess.scheduled_start DESC
            LIMIT %s
            """,
            [faculty_id, bounded_limit],
        ).fetchall()
        return [dict(row) for row in rows]


def faculty_register(faculty_id: UUID, course_offering_id: UUID) -> dict:
    with _connect() as conn:
        _require_faculty_offering(conn, faculty_id, course_offering_id)
        offering = conn.execute(
            """
            SELECT co.id AS course_offering_id, c.code AS course_code,
                   c.name AS course_name, sec.code AS section_code
            FROM course_offerings co
            JOIN courses c ON c.id = co.course_id
            JOIN sections sec ON sec.id = co.section_id
            WHERE co.id = %s
            """,
            [course_offering_id],
        ).fetchone()
        sessions = conn.execute(
            """
            SELECT * FROM (
                SELECT id, scheduled_start, state::text AS state,
                       to_char(scheduled_start, 'DD Mon') AS label
                FROM attendance_sessions
                WHERE course_offering_id = %s
                  AND state IN ('SYNCING', 'RECONCILED')
                  AND scheduled_start <= now()
                ORDER BY scheduled_start DESC
                LIMIT 40
            ) latest ORDER BY scheduled_start
            """,
            [course_offering_id],
        ).fetchall()
        session_ids = [row["id"] for row in sessions]
        students = conn.execute(
            """
            SELECT s.id AS student_id, s.roll_number, s.display_name
            FROM enrollments e
            JOIN students s ON s.id = e.student_id
            WHERE e.course_offering_id = %s AND e.active = true
            ORDER BY s.roll_number
            LIMIT 500
            """,
            [course_offering_id],
        ).fetchall()
        records = []
        if session_ids:
            records = conn.execute(
                """
                SELECT attendance_session_id, student_id, status::text AS status
                FROM attendance_records
                WHERE attendance_session_id = ANY(%s)
                """,
                [session_ids],
            ).fetchall()
        by_student_session = {
            (str(row["student_id"]), str(row["attendance_session_id"])): row["status"]
            for row in records
        }
        session_payload = [
            {
                "id": row["id"],
                "label": row["label"],
                "scheduled_start": row["scheduled_start"],
                "state": row["state"],
            }
            for row in sessions
        ]
        student_payload = []
        for student in students:
            statuses = {
                str(session["id"]): by_student_session.get(
                    (str(student["student_id"]), str(session["id"]))
                )
                for session in sessions
            }
            present = sum(1 for status in statuses.values() if status == "PRESENT")
            absent = sum(1 for status in statuses.values() if status == "ABSENT")
            total = present + absent
            percentage = 0.0 if total == 0 else round((present / total) * 100, 2)
            student_payload.append(
                {
                    "student_id": student["student_id"],
                    "roll_number": student["roll_number"],
                    "display_name": student["display_name"],
                    "present": present,
                    "absent": absent,
                    "percentage": percentage,
                    "statuses": statuses,
                }
            )
        return {
            "course_offering_id": offering["course_offering_id"],
            "course_code": offering["course_code"],
            "course_name": offering["course_name"],
            "section_code": offering["section_code"],
            "sessions": session_payload,
            "students": student_payload,
        }


def attest_student(faculty_id: UUID, session_id: UUID, student_id: UUID, reason: str) -> dict:
    with _connect() as conn:
        with conn.transaction():
            session = _session_by_id(conn, session_id)
            if str(session["created_by_faculty_id"]) != str(faculty_id):
                raise ApiError("FACULTY_NOT_AUTHORIZED", "Faculty cannot attest this session.", 403)
            if session["state"] not in ("ACTIVE", "SYNCING"):
                raise ApiError("SESSION_RECONCILED", "This attendance session can no longer be amended.", 409)
            rostered = conn.execute(
                "SELECT 1 FROM attendance_session_roster WHERE attendance_session_id = %s AND student_id = %s",
                [session_id, student_id],
            ).fetchone()
            if rostered is None:
                raise ApiError("STUDENT_NOT_IN_ROSTER", "Student is not in this session roster.", 403)
            record = conn.execute(
                """
                INSERT INTO attendance_records (
                    attendance_session_id, student_id, status, method, recorded_at
                )
                VALUES (%s, %s, 'PRESENT', 'FACULTY_ATTESTATION', now())
                ON CONFLICT (attendance_session_id, student_id)
                DO UPDATE SET status = 'PRESENT',
                              method = CASE
                                WHEN attendance_records.status = 'PRESENT'
                                 AND attendance_records.method = 'SECURE_PROOF'
                                THEN attendance_records.method
                                ELSE 'FACULTY_ATTESTATION'
                              END,
                              recorded_at = CASE
                                WHEN attendance_records.status = 'PRESENT' THEN attendance_records.recorded_at
                                ELSE now()
                              END,
                              updated_at = now()
                RETURNING id, attendance_session_id, student_id, status::text AS status,
                          method::text AS method, recorded_at
                """,
                [session_id, student_id],
            ).fetchone()
            conn.execute(
                """
                INSERT INTO faculty_attestations (
                    attendance_record_id, attendance_session_id, student_id,
                    faculty_id, reason, attested_at
                )
                VALUES (%s, %s, %s, %s, %s, now())
                ON CONFLICT (attendance_record_id) DO NOTHING
                """,
                [record["id"], session_id, student_id, faculty_id, reason],
            )
            _audit(conn, "FACULTY_ATTESTATION_CREATED", "attendance_record", record["id"], str(faculty_id))
            return dict(record)


def qr_payload_for(session_id: UUID, now: datetime | None = None) -> dict:
    current = now or datetime.now(UTC)
    with _connect() as conn:
        session = _session_by_id(conn, session_id)
        if session["state"] != "ACTIVE":
            raise ApiError("SESSION_CLOSED", "Attendance session is not active.", 409)
        auth = _authorization_for_session(conn, session_id, include_private=True)
        if auth is None:
            raise ApiError("SESSION_AUTHORIZATION_NOT_FOUND", "Session authorization is missing.", 404)
        valid_from = _aware(auth["valid_from"])
        valid_until = _aware(auth["valid_until"])
        if current < valid_from or current > valid_until:
            raise ApiError("SESSION_AUTHORIZATION_EXPIRED", "Session authorization is not valid.", 409)
        origin = javascript_date_precision(_aware(session["started_at"]))
        epoch = epoch_for(current, origin)
        issued_at, expires_at = epoch_window(origin, epoch)
        challenge = _qr_challenge(session_id, epoch, auth["session_public_key"])
        canonical = canonical_attendance_qr(
            session_id=session_id,
            epoch=epoch,
            issued_at=issued_at.isoformat(),
            expires_at=expires_at.isoformat(),
            challenge=challenge,
            key_id=auth["key_id"],
        )
        signature = sign(_signing_key_from_b64(auth["session_private_key"]), canonical)
        public_auth = dict(auth)
        public_auth.pop("session_private_key", None)
        return {
            "protocol_version": ATTENDANCE_QR_PROTOCOL,
            "session_id": session_id,
            "epoch": epoch,
            "issued_at": issued_at,
            "expires_at": expires_at,
            "challenge": challenge,
            "key_id": auth["key_id"],
            "signature": signature,
            "session_authorization": public_auth,
        }


def submit_attendance_claim(payload: dict) -> dict:
    with _connect() as conn:
        with conn.transaction():
            session = _session_by_id(conn, payload["session_id"])
            if session["state"] != "ACTIVE":
                raise ApiError("SESSION_CLOSED", "Attendance session is not active.", 409)
            enrolled = conn.execute(
                """
                SELECT 1 FROM attendance_session_roster
                WHERE attendance_session_id = %s AND student_id = %s
                """,
                [payload["session_id"], payload["student_id"]],
            ).fetchone()
            if enrolled is None:
                raise ApiError("NOT_ENROLLED", "Student is not enrolled for this session.", 403)
            device = conn.execute(
                """
                SELECT id, public_key FROM device_registrations
                WHERE id = %s AND student_id = %s AND status = 'ACTIVE'
                """,
                [payload["device_registration_id"], payload["student_id"]],
            ).fetchone()
            if device is None:
                raise ApiError("DEVICE_NOT_AUTHORIZED", "Attendance device is not authorized.", 403)
            _validate_signed_qr_evidence(conn, payload, session)
            canonical = canonical_attendance_claim(
                claim_id=payload["claim_id"],
                session_id=payload["session_id"],
                student_id=payload["student_id"],
                device_registration_id=payload["device_registration_id"],
                qr_epoch=payload["qr_epoch"],
                qr_challenge=payload["qr_challenge"],
                qr_issued_at=payload["qr_issued_at"],
                qr_expires_at=payload["qr_expires_at"],
                qr_signature=payload["qr_signature"],
                qr_captured_at=payload["qr_captured_at"],
                claim_created_at=payload["claim_created_at"],
                claim_expires_at=payload["claim_expires_at"],
            )
            if not verify_signature(device["public_key"], canonical, payload["device_signature"]):
                raise ApiError("INVALID_CLAIM_SIGNATURE", "Claim signature is invalid.", 400)
            row = conn.execute(
                """
                INSERT INTO attendance_claims (
                    claim_id, attendance_session_id, student_id, device_registration_id,
                    qr_epoch, qr_challenge, qr_issued_at, qr_expires_at,
                    qr_signature, qr_captured_at, claim_created_at,
                    claim_expires_at, claim_state, device_signature
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, 'AWAITING_PRESENCE', %s)
                ON CONFLICT (attendance_session_id, student_id)
                DO UPDATE SET updated_at = now()
                RETURNING claim_id, attendance_session_id AS session_id,
                          claim_state::text AS claim_state, claim_expires_at
                """,
                [
                    payload["claim_id"],
                    payload["session_id"],
                    payload["student_id"],
                    payload["device_registration_id"],
                    payload["qr_epoch"],
                    payload["qr_challenge"],
                    payload["qr_issued_at"],
                    payload["qr_expires_at"],
                    payload["qr_signature"],
                    payload["qr_captured_at"],
                    payload["claim_created_at"],
                    payload["claim_expires_at"],
                    payload["device_signature"],
                ],
            ).fetchone()
            _audit(conn, "ATTENDANCE_CLAIM_CAPTURED", "attendance_claim", row["claim_id"], str(payload["student_id"]))
            return dict(row)


def submit_attendance_proof_submission(submission: dict) -> dict:
    if submission["protocol_version"] != ATTENDANCE_PROOF_PROTOCOL:
        return _proof_rejection(
            submission.get("proof", {}).get("proof_id"),
            "UNSUPPORTED_PROTOCOL",
            retryable=False,
        )
    try:
        with _connect() as conn:
            with conn.transaction():
                return _reconcile_attendance_proof(conn, submission)
    except ApiError as exc:
        return _proof_rejection(
            submission.get("proof", {}).get("proof_id"),
            exc.code,
            retryable=exc.code in {
                "SESSION_ACTIVATION_PENDING",
                "COORDINATION_UNAVAILABLE",
                "TEMPORARY_DATABASE_ERROR",
            },
        )
    except psycopg.errors.IntegrityError:
        # e.g. a second claim_id for the same (session, student): permanent, must not poison the batch.
        return _proof_rejection(submission.get("proof", {}).get("proof_id"), "CLAIM_CONFLICT", retryable=False)
    except psycopg.Error:
        return _proof_rejection(submission.get("proof", {}).get("proof_id"), "TEMPORARY_DATABASE_ERROR", retryable=True)


def submit_attendance_proof_batch(submissions: list[dict]) -> list[dict]:
    bounded = submissions[:50]
    return [submit_attendance_proof_submission(item) for item in bounded]


def _reconcile_attendance_proof(conn, submission: dict) -> dict:
    claim_payload = submission["claim"]
    challenge = submission["challenge"]
    response = submission["response"]
    proof = submission["proof"]

    existing = conn.execute(
        """
        SELECT ap.proof_id, ar.id AS attendance_record_id, ar.status::text AS status,
               ar.method::text AS method, ar.recorded_at,
               EXTRACT(EPOCH FROM ar.updated_at)::bigint AS server_version
        FROM attendance_proofs ap
        JOIN attendance_records ar
          ON ar.attendance_session_id = ap.attendance_session_id
         AND ar.student_id = ap.student_id
        WHERE ap.proof_id = %s AND ap.sync_state = 'SERVER_VERIFIED'
        """,
        [proof["proof_id"]],
    ).fetchone()
    if existing is not None:
        return {
            "proof_id": existing["proof_id"],
            "result": "ALREADY_ACCEPTED",
            "attendance_record_id": existing["attendance_record_id"],
            "authoritative_status": existing["status"],
            "attendance_method": existing["method"],
            "recorded_at": existing["recorded_at"],
            "server_version": existing["server_version"],
            "retryable": False,
        }

    _validate_proof_bindings(claim_payload, challenge, response, proof)
    session = _session_by_id(conn, proof["session_id"])
    rostered = conn.execute(
        """
        SELECT 1 FROM attendance_session_roster
        WHERE attendance_session_id = %s AND student_id = %s
        """,
        [proof["session_id"], proof["student_id"]],
    ).fetchone()
    if rostered is None:
        raise ApiError("STUDENT_NOT_ELIGIBLE", "Student is not in the expected roster.", 403)

    device = conn.execute(
        """
        SELECT id, public_key, status::text AS status, revoked_at
        FROM device_registrations
        WHERE id = %s AND student_id = %s
        """,
        [proof["device_registration_id"], proof["student_id"]],
    ).fetchone()
    if device is None:
        raise ApiError("DEVICE_REVOKED", "Attendance device is not active for this student.", 403)

    _ensure_device_was_valid_at_capture(device, claim_payload)
    _ensure_claim_for_proof(conn, claim_payload, device["public_key"], session)
    _verify_presence_and_proof_signatures(device["public_key"], challenge, response, proof)

    conn.execute(
        """
        INSERT INTO presence_challenges (
            challenge_id, attendance_session_id, attendance_claim_id, presence_epoch,
            nonce, issued_at, expires_at, transport, host_public_key, state
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, 'VERIFIED')
        ON CONFLICT (challenge_id)
        DO UPDATE SET state = 'VERIFIED'
        """,
        [
            challenge["challenge_id"],
            challenge["session_id"],
            challenge["claim_id"],
            challenge["presence_epoch"],
            challenge["nonce"],
            challenge["issued_at"],
            challenge["expires_at"],
            challenge["transport"],
            challenge["host_public_key"],
        ],
    )
    conn.execute(
        """
        INSERT INTO presence_responses (
            response_id, challenge_id, attendance_session_id, attendance_claim_id,
            device_registration_id, presence_epoch, responded_at, transport,
            challenge_nonce, host_public_key, device_signature, state
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, 'VERIFIED')
        ON CONFLICT (response_id)
        DO UPDATE SET state = 'VERIFIED'
        """,
        [
            response["response_id"],
            response["challenge_id"],
            response["session_id"],
            response["claim_id"],
            response["device_registration_id"],
            response["presence_epoch"],
            response["responded_at"],
            response["transport"],
            response["challenge_nonce"],
            response["host_public_key"],
            response["device_signature"],
        ],
    )
    conn.execute(
        """
        INSERT INTO attendance_proofs (
            proof_id, attendance_claim_id, attendance_session_id, student_id,
            device_registration_id, presence_challenge_id, presence_response_id,
            proof_created_at, final_device_signature, sync_state
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, 'SERVER_VERIFIED')
        ON CONFLICT (proof_id)
        DO UPDATE SET sync_state = 'SERVER_VERIFIED', updated_at = now()
        """,
        [
            proof["proof_id"],
            proof["claim_id"],
            proof["session_id"],
            proof["student_id"],
            proof["device_registration_id"],
            proof["presence_challenge_id"],
            proof["presence_response_id"],
            proof["proof_created_at"],
            proof["final_device_signature"],
        ],
    )
    record = conn.execute(
        """
        INSERT INTO attendance_records (
            attendance_session_id, student_id, device_registration_id, status,
            method, technical_state, recorded_at
        )
        VALUES (%s, %s, %s, 'PRESENT', 'SECURE_PROOF', 'SERVER_VERIFIED', %s)
        ON CONFLICT (attendance_session_id, student_id)
        DO UPDATE SET status = 'PRESENT',
                      method = CASE
                        WHEN attendance_records.method = 'FACULTY_ATTESTATION'
                        THEN attendance_records.method
                        ELSE 'SECURE_PROOF'
                      END,
                      device_registration_id = COALESCE(
                        attendance_records.device_registration_id,
                        excluded.device_registration_id
                      ),
                      technical_state = 'SERVER_VERIFIED',
                      updated_at = now()
        RETURNING id, status::text AS status, method::text AS method, recorded_at,
                  EXTRACT(EPOCH FROM updated_at)::bigint AS server_version
        """,
        [
            proof["session_id"],
            proof["student_id"],
            proof["device_registration_id"],
            proof["proof_created_at"],
        ],
    ).fetchone()
    conn.execute(
        "UPDATE attendance_claims SET claim_state = 'CONSUMED', updated_at = now() WHERE claim_id = %s",
        [proof["claim_id"]],
    )
    _audit(conn, "ATTENDANCE_PROOF_ACCEPTED", "attendance_proof", proof["proof_id"], str(proof["student_id"]))
    return {
        "proof_id": proof["proof_id"],
        "result": "ACCEPTED",
        "attendance_record_id": record["id"],
        "authoritative_status": record["status"],
        "attendance_method": record["method"],
        "recorded_at": record["recorded_at"],
        "server_version": record["server_version"],
        "retryable": False,
    }


def _validate_proof_bindings(claim_payload: dict, challenge: dict, response: dict, proof: dict) -> None:
    if proof["claim_id"] != claim_payload["claim_id"]:
        raise ApiError("PROOF_MALFORMED", "Proof claim does not match bundled claim.", 400)
    if proof["session_id"] != claim_payload["session_id"]:
        raise ApiError("PROOF_MALFORMED", "Proof session does not match bundled claim.", 400)
    if proof["student_id"] != claim_payload["student_id"]:
        raise ApiError("PROOF_MALFORMED", "Proof student does not match bundled claim.", 400)
    if proof["device_registration_id"] != claim_payload["device_registration_id"]:
        raise ApiError("DEVICE_MISMATCH", "Proof device does not match bundled claim.", 400)
    if challenge["challenge_id"] != proof["presence_challenge_id"]:
        raise ApiError("PRESENCE_INVALID", "Presence challenge does not match proof.", 400)
    if response["response_id"] != proof["presence_response_id"]:
        raise ApiError("PRESENCE_INVALID", "Presence response does not match proof.", 400)
    for payload in (challenge, response):
        if payload["session_id"] != proof["session_id"] or payload["claim_id"] != proof["claim_id"]:
            raise ApiError("PRESENCE_INVALID", "Presence evidence is not bound to this proof.", 400)
    if response["challenge_id"] != challenge["challenge_id"]:
        raise ApiError("PRESENCE_INVALID", "Presence response challenge mismatch.", 400)
    if response["challenge_nonce"] != challenge["nonce"]:
        raise ApiError("PRESENCE_INVALID", "Presence nonce mismatch.", 400)
    if response["device_registration_id"] != proof["device_registration_id"]:
        raise ApiError("DEVICE_MISMATCH", "Presence response device mismatch.", 400)


def _ensure_claim_for_proof(conn, payload: dict, public_key: str, session: dict) -> None:
    now = datetime.now(UTC)
    captured_at = _aware(payload["qr_captured_at"])
    created_at = _aware(payload["claim_created_at"])
    expires_at = _aware(payload["claim_expires_at"])
    if session["state"] == "CREATED":
        raise ApiError(
            "SESSION_ACTIVATION_PENDING",
            "The offline faculty session has not synchronized yet.",
            409,
        )
    if session["state"] not in ("ACTIVE", "SYNCING"):
        raise ApiError("SESSION_RECONCILED", "This attendance session no longer accepts proofs.", 409)
    reconcile_until = session.get("reconcile_until")
    if session["state"] == "SYNCING" and (
        reconcile_until is None or now > _aware(reconcile_until)
    ):
        raise ApiError("RECONCILIATION_WINDOW_CLOSED", "The reconciliation window has closed.", 409)
    if created_at > expires_at:
        raise ApiError("CLAIM_EXPIRED", "Claim timestamps are invalid.", 409)
    if created_at < captured_at or created_at > captured_at + timedelta(seconds=60 + CLOCK_SKEW_SECONDS):
        raise ApiError("CLAIM_EXPIRED", "Claim creation is outside the allowed 60-second window.", 409)
    _validate_signed_qr_evidence(conn, payload, session)
    canonical = canonical_attendance_claim(
        claim_id=payload["claim_id"],
        session_id=payload["session_id"],
        student_id=payload["student_id"],
        device_registration_id=payload["device_registration_id"],
        qr_epoch=payload["qr_epoch"],
        qr_challenge=payload["qr_challenge"],
        qr_issued_at=payload["qr_issued_at"],
        qr_expires_at=payload["qr_expires_at"],
        qr_signature=payload["qr_signature"],
        qr_captured_at=payload["qr_captured_at"],
        claim_created_at=payload["claim_created_at"],
        claim_expires_at=payload["claim_expires_at"],
    )
    if not verify_signature(public_key_b64url=public_key, payload=canonical, signature_b64url=payload["device_signature"]):
        raise ApiError("INVALID_SIGNATURE", "Claim signature is invalid.", 400)
    conn.execute(
        """
        INSERT INTO attendance_claims (
            claim_id, attendance_session_id, student_id, device_registration_id,
            qr_epoch, qr_challenge, qr_issued_at, qr_expires_at,
            qr_signature, qr_captured_at, claim_created_at,
            claim_expires_at, claim_state, device_signature
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, 'PROOF_READY', %s)
        ON CONFLICT (attendance_session_id, student_id)
        DO UPDATE SET claim_state = CASE
              WHEN attendance_claims.claim_state = 'CONSUMED' THEN 'CONSUMED'::attendance_claim_state
              ELSE 'PROOF_READY'::attendance_claim_state
            END,
            updated_at = now()
        """,
        [
            payload["claim_id"],
            payload["session_id"],
            payload["student_id"],
            payload["device_registration_id"],
            payload["qr_epoch"],
            payload["qr_challenge"],
            payload["qr_issued_at"],
            payload["qr_expires_at"],
            payload["qr_signature"],
            payload["qr_captured_at"],
            payload["claim_created_at"],
            payload["claim_expires_at"],
            payload["device_signature"],
        ],
    )


def _validate_signed_qr_evidence(conn, payload: dict, session: dict) -> None:
    """Validate the server-issued QR, not merely a device-signed copy of it."""
    issued_at = _aware(payload["qr_issued_at"])
    expires_at = _aware(payload["qr_expires_at"])
    captured_at = _aware(payload["qr_captured_at"])
    authorization = _authorization_for_session(conn, payload["session_id"], include_private=False)
    if authorization is None:
        raise ApiError("SESSION_AUTHORIZATION_NOT_FOUND", "Session authorization is missing.", 404)
    if authorization["key_id"] != session.get("key_id", authorization["key_id"]):
        raise ApiError("QR_KEY_MISMATCH", "QR signing key does not match this session.", 400)
    if expires_at <= issued_at or expires_at - issued_at > timedelta(seconds=QR_EPOCH_SECONDS):
        raise ApiError("QR_EXPIRED", "QR validity window is invalid.", 409)
    if not (issued_at - timedelta(seconds=CLOCK_SKEW_SECONDS) <= captured_at <= expires_at + timedelta(seconds=CLOCK_SKEW_SECONDS)):
        raise ApiError("QR_EXPIRED", "QR was not captured during its signed validity window.", 409)
    origin = javascript_date_precision(_aware(session["started_at"]))
    expected_epoch = epoch_for(issued_at, origin)
    expected_issued_at, expected_expires_at = epoch_window(origin, expected_epoch)
    expected_challenge = _qr_challenge(session["id"], expected_epoch, authorization["session_public_key"])
    if (
        payload["qr_epoch"] != expected_epoch
        or issued_at != expected_issued_at
        or expires_at != expected_expires_at
        or payload["qr_challenge"] != expected_challenge
    ):
        raise ApiError("QR_TAMPERED", "QR evidence does not match the issued epoch.", 400)
    canonical = canonical_attendance_qr(
        session_id=session["id"],
        epoch=payload["qr_epoch"],
        issued_at=payload["qr_issued_at"],
        expires_at=payload["qr_expires_at"],
        challenge=payload["qr_challenge"],
        key_id=authorization["key_id"],
    )
    if not verify(authorization["session_public_key"], canonical, payload["qr_signature"]):
        raise ApiError("INVALID_QR_SIGNATURE", "QR signature could not be verified.", 400)


def _ensure_device_was_valid_at_capture(device: dict, claim_payload: dict) -> None:
    if device["status"] == "ACTIVE":
        return
    revoked_at = device.get("revoked_at")
    qr_expires_at = _aware(claim_payload["qr_expires_at"])
    if device["status"] == "REVOKED" and revoked_at is not None and qr_expires_at < _aware(revoked_at):
        return
    raise ApiError("DEVICE_REVOKED", "Attendance device was not valid when this QR was scanned.", 403)


def _verify_presence_and_proof_signatures(public_key: str, challenge: dict, response: dict, proof: dict) -> None:
    responded_at = _aware(response["responded_at"])
    challenge_issued_at = _aware(challenge["issued_at"])
    challenge_expires_at = _aware(challenge["expires_at"])
    proof_created_at = _aware(proof["proof_created_at"])
    if not (challenge_issued_at <= responded_at <= challenge_expires_at):
        raise ApiError("PRESENCE_EXPIRED", "Presence response is outside the challenge window.", 409)
    if proof_created_at < responded_at:
        raise ApiError("PROOF_MALFORMED", "Proof cannot predate presence response.", 400)
    response_payload = canonical_presence_response(
        response_id=response["response_id"],
        challenge_id=response["challenge_id"],
        session_id=response["session_id"],
        claim_id=response["claim_id"],
        device_registration_id=response["device_registration_id"],
        presence_epoch=response["presence_epoch"],
        responded_at=response["responded_at"],
        transport=response["transport"],
        challenge_nonce=response["challenge_nonce"],
        host_public_key=response["host_public_key"],
    )
    if not verify_signature(public_key_b64url=public_key, payload=response_payload, signature_b64url=response["device_signature"]):
        raise ApiError("INVALID_SIGNATURE", "Presence response signature is invalid.", 400)
    proof_payload = canonical_attendance_proof(
        proof_id=proof["proof_id"],
        claim_id=proof["claim_id"],
        session_id=proof["session_id"],
        student_id=proof["student_id"],
        device_registration_id=proof["device_registration_id"],
        presence_challenge_id=proof["presence_challenge_id"],
        presence_response_id=proof["presence_response_id"],
        proof_created_at=proof["proof_created_at"],
    )
    if not verify_signature(public_key_b64url=public_key, payload=proof_payload, signature_b64url=proof["final_device_signature"]):
        raise ApiError("INVALID_SIGNATURE", "Attendance proof signature is invalid.", 400)


def _proof_rejection(proof_id, error_code: str, retryable: bool) -> dict:
    return {
        "proof_id": proof_id,
        "result": "REJECTED",
        "attendance_record_id": None,
        "authoritative_status": None,
        "attendance_method": None,
        "recorded_at": None,
        "server_version": None,
        "error_code": error_code,
        "retryable": retryable,
    }


def trust_root() -> dict:
    return {
        "key_id": institution_key_id(),
        "algorithm": "Ed25519",
        "public_key": institution_public_key(),
    }


def _combine(day: date, value: time) -> datetime:
    return datetime.combine(day, value, tzinfo=UTC)


def _snapshot_roster(conn, session_id: UUID) -> None:
    conn.execute(
        """
        INSERT INTO attendance_session_roster (
            attendance_session_id, enrollment_id, student_id, course_offering_id,
            roll_number_snapshot, student_name_snapshot, section_code_snapshot,
            course_code_snapshot, course_name_snapshot
        )
        SELECT sess.id, e.id, s.id, co.id, s.roll_number, s.display_name,
               sec.code, c.code, c.name
        FROM attendance_sessions sess
        JOIN course_offerings co ON co.id = sess.course_offering_id
        JOIN courses c ON c.id = co.course_id
        JOIN sections sec ON sec.id = co.section_id
        JOIN enrollments e ON e.course_offering_id = co.id AND e.active = true
        JOIN students s ON s.id = e.student_id
        WHERE sess.id = %s
        ON CONFLICT DO NOTHING
        """,
        [session_id],
    )


def _require_faculty_offering(conn, faculty_id: UUID, course_offering_id: UUID) -> None:
    authorized = conn.execute(
        """
        SELECT 1
        FROM faculty_assignments
        WHERE faculty_id = %s
          AND course_offering_id = %s
          AND active = true
        LIMIT 1
        """,
        [faculty_id, course_offering_id],
    ).fetchone()
    if authorized is None:
        raise ApiError("FACULTY_NOT_AUTHORIZED", "Faculty cannot access this course.", 403)


def _ensure_authorization(conn, session_id: UUID, faculty_id: UUID, course_offering_id: UUID, scheduled_start: datetime, scheduled_end: datetime) -> dict:
    now = datetime.now(UTC)
    existing = _authorization_for_session(conn, session_id, include_private=True)
    if existing is not None:
        valid_from = _aware(existing["valid_from"])
        valid_until = _aware(existing["valid_until"])
        maximum_lifetime = timedelta(seconds=SESSION_AUTHORIZATION_MAX_SECONDS)
        if valid_until - valid_from <= maximum_lifetime:
            return existing

        # Repair authorizations issued by older builds that exceeded the
        # mobile verifier's bounded trust window.
        valid_from = valid_until - maximum_lifetime
        conn.execute(
            "UPDATE session_authorizations SET valid_from = %s WHERE id = %s",
            [valid_from, existing["authorization_id"]],
        )
        repaired = _authorization_for_session(conn, session_id, include_private=True)
        canonical = canonical_session_authorization(
            authorization_id=repaired["authorization_id"],
            session_id=repaired["session_id"],
            course_offering_id=repaired["course_offering_id"],
            faculty_id=repaired["faculty_id"],
            valid_from=repaired["valid_from"].isoformat(),
            valid_until=repaired["valid_until"].isoformat(),
            key_id=repaired["key_id"],
            session_public_key=repaired["session_public_key"],
        )
        conn.execute(
            "UPDATE session_authorizations SET server_signature = %s WHERE id = %s",
            [sign(institution_signing_key(), canonical), repaired["authorization_id"]],
        )
        return _authorization_for_session(conn, session_id, include_private=True)
    key = SigningKey.generate()
    session_public_key = _b64(bytes(key.verify_key))
    session_private_key = _b64(bytes(key))
    valid_from = min(scheduled_start - timedelta(minutes=15), now - timedelta(minutes=1))
    valid_until = max(scheduled_end + timedelta(minutes=15), now + timedelta(hours=2))
    maximum_lifetime = timedelta(seconds=SESSION_AUTHORIZATION_MAX_SECONDS)
    if valid_until - valid_from > maximum_lifetime:
        valid_from = valid_until - maximum_lifetime
    row = conn.execute(
        """
        INSERT INTO session_authorizations (
            attendance_session_id, faculty_id, course_offering_id, key_id,
            session_public_key, session_private_key, server_signature,
            valid_from, valid_until
        )
        VALUES (%s, %s, %s, %s, %s, %s, '', %s, %s)
        RETURNING id
        """,
        [session_id, faculty_id, course_offering_id, f"session:{session_id}", session_public_key, session_private_key, valid_from, valid_until],
    ).fetchone()
    auth = _authorization_for_session(conn, session_id, include_private=True)
    canonical = canonical_session_authorization(
        authorization_id=row["id"],
        session_id=auth["session_id"],
        course_offering_id=auth["course_offering_id"],
        faculty_id=auth["faculty_id"],
        valid_from=auth["valid_from"].isoformat(),
        valid_until=auth["valid_until"].isoformat(),
        key_id=auth["key_id"],
        session_public_key=auth["session_public_key"],
    )
    signature = sign(institution_signing_key(), canonical)
    conn.execute(
        "UPDATE session_authorizations SET server_signature = %s WHERE id = %s",
        [signature, row["id"]],
    )
    return _authorization_for_session(conn, session_id, include_private=True)


def _authorization_for_session(conn, session_id: UUID, include_private: bool) -> dict | None:
    row = conn.execute(
        """
        SELECT id AS authorization_id, %s AS protocol_version,
               attendance_session_id AS session_id, course_offering_id, faculty_id,
               valid_from, valid_until, key_id, session_public_key,
               session_private_key, server_signature
        FROM session_authorizations
        WHERE attendance_session_id = %s AND revoked_at IS NULL
        """,
        [SESSION_AUTHORIZATION_PROTOCOL, session_id],
    ).fetchone()
    if row is None:
        return None
    result = dict(row)
    if not include_private:
        result.pop("session_private_key", None)
    return result


def _session_by_id(conn, session_id: UUID) -> dict:
    row = conn.execute(
        """
        SELECT sess.id, sess.course_offering_id, sess.created_by_faculty_id,
               c.code AS course_code, c.name AS course_name, sec.code AS section_code,
               te.room, sess.scheduled_start, sess.scheduled_end, sess.started_at,
               sess.closed_at, sess.reconcile_until, sess.reconciliation_state,
               sess.state::text AS state
        FROM attendance_sessions sess
        JOIN course_offerings co ON co.id = sess.course_offering_id
        JOIN courses c ON c.id = co.course_id
        JOIN sections sec ON sec.id = co.section_id
        LEFT JOIN timetable_entries te
          ON te.course_offering_id = sess.course_offering_id
         AND te.day_of_week = EXTRACT(ISODOW FROM sess.scheduled_start)::int
        WHERE sess.id = %s
        """,
        [session_id],
    ).fetchone()
    if row is None:
        raise ApiError("SESSION_NOT_FOUND", "Attendance session was not found.", 404)
    return dict(row)


def _qr_challenge(session_id: UUID, epoch: int, session_public_key: str) -> str:
    return _b64(f"{session_id}:{epoch}:{session_public_key}".encode())[:43]


def _signing_key_from_b64(value: str):
    from nacl.signing import SigningKey
    from .device_crypto import b64url_decode

    return SigningKey(b64url_decode(value))


def _b64(value: bytes) -> str:
    from .device_crypto import b64url_encode

    return b64url_encode(value)


def _aware(value: datetime | str) -> datetime:
    if isinstance(value, str):
        try:
            value = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError as exc:
            raise ApiError("PROOF_MALFORMED", "A signed timestamp is not valid ISO 8601.", 400) from exc
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)


_STUDENT_AUDIT_EVENTS = {"ATTENDANCE_CLAIM_CAPTURED", "ATTENDANCE_PROOF_ACCEPTED"}


def _audit(conn, event_type: str, entity_type: str, entity_id, actor_id: str) -> None:
    actor_type = "student" if event_type in _STUDENT_AUDIT_EVENTS else "faculty"
    conn.execute(
        """
        INSERT INTO audit_logs (event_type, entity_type, entity_id, actor_type, actor_id, metadata)
        VALUES (%s, %s, %s, %s, %s, '{}'::jsonb)
        """,
        [event_type, entity_type, entity_id, actor_type, actor_id],
    )
