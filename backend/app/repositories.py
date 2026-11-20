from datetime import UTC, datetime
from uuid import UUID

from .db import connect, fetch_all, fetch_one
from .domain import attendance_percentage
from .errors import ApiError
from .institution_identity import institution_email_allowed


def get_student(student_id: UUID) -> dict:
    row = fetch_one(
        """
        SELECT id, roll_number, institutional_email, display_name
        FROM students
        WHERE id = %s AND active = true
        """,
        [student_id],
    )
    if row is None:
        raise ApiError("STUDENT_NOT_FOUND", "Development student was not found.", 404)
    return row


def get_student_by_email(email: str) -> dict:
    normalized = email.strip().lower()
    if not institution_email_allowed(normalized):
        raise ApiError("INVALID_INSTITUTION_EMAIL", "Use your institutional email address.", 400)
    row = fetch_one(
        """
        SELECT id, roll_number, institutional_email, display_name
        FROM students
        WHERE lower(institutional_email) = %s AND active = true
        """,
        [normalized],
    )
    if row is None:
        raise ApiError("STUDENT_NOT_FOUND", "No active student record matches this Institution email.", 404)
    return row


def get_faculty_by_identity(identity: str) -> dict:
    normalized = identity.strip().lower()
    row = fetch_one(
        """
        SELECT id, employee_code, institutional_email, display_name
        FROM faculty
        WHERE active = true
          AND (
            lower(id::text) = %s
            OR lower(employee_code) = %s
            OR lower(institutional_email) = %s
          )
        """,
        [normalized, normalized, normalized],
    )
    if row is None:
        raise ApiError("FACULTY_NOT_FOUND", "No active faculty account matches this identity.", 404)
    return row


def bootstrap_student_sync(student_id: UUID) -> dict:
    """Full bootstrap payload, computed once over a single (pooled) connection."""
    student = get_student(student_id)
    with connect() as conn:
        def q(sql, params=()):
            return conn.execute(sql, params).fetchall()

        return _bootstrap_payload(student_id, student, q)


def student_enrollments(student_id: UUID) -> list[dict]:
    with connect() as conn:
        return _enrollments(student_id, lambda sql, params=(): conn.execute(sql, params).fetchall())


def student_attendance_records(student_id: UUID) -> list[dict]:
    with connect() as conn:
        q = lambda sql, params=(): conn.execute(sql, params).fetchall()  # noqa: E731
        if not _enrollments(student_id, q):
            return []
        return _attendance_records(student_id, q)


def student_attendance_summaries(student_id: UUID) -> list[dict]:
    with connect() as conn:
        q = lambda sql, params=(): conn.execute(sql, params).fetchall()  # noqa: E731
        if not _enrollments(student_id, q):
            return []
        return _attendance_summaries(student_id, q)


def _enrollments(student_id, q) -> list[dict]:
    return q(
        """
        SELECT e.id, e.student_id, e.course_offering_id
        FROM enrollments e
        WHERE e.student_id = %s AND e.active = true
        ORDER BY e.created_at, e.id
        """,
        [student_id],
    )


def _attendance_records(student_id, q) -> list[dict]:
    return q(
        """
        SELECT ar.id, ar.attendance_session_id, ar.student_id, ar.status::text AS status,
               ar.method::text AS method, ar.recorded_at
        FROM attendance_records ar
        JOIN attendance_sessions sess ON sess.id = ar.attendance_session_id
        WHERE ar.student_id = %s AND sess.state IN ('SYNCING', 'RECONCILED')
        ORDER BY ar.recorded_at, ar.id
        """,
        [student_id],
    )


def _attendance_summaries(student_id, q) -> list[dict]:
    summaries = q(
        """
        SELECT c.id AS course_id, c.code AS course_code, c.name AS course_name,
               COUNT(ar.id)::int AS total_classes,
               COUNT(ar.id) FILTER (WHERE ar.status = 'PRESENT')::int AS present,
               COUNT(ar.id) FILTER (WHERE ar.status = 'ABSENT')::int AS absent
        FROM attendance_records ar
        JOIN attendance_sessions sess ON sess.id = ar.attendance_session_id
        JOIN course_offerings co ON co.id = sess.course_offering_id
        JOIN courses c ON c.id = co.course_id
        WHERE ar.student_id = %s AND sess.state IN ('SYNCING', 'RECONCILED')
        GROUP BY c.id, c.code, c.name
        ORDER BY c.code
        """,
        [student_id],
    )
    for row in summaries:
        row["percentage"] = attendance_percentage(row["present"], row["absent"])
    return summaries


def _bootstrap_payload(student_id, student, q) -> dict:
    enrollments = _enrollments(student_id, q)
    offering_ids = [row["course_offering_id"] for row in enrollments]
    if not offering_ids:
        return _empty_bootstrap(student)

    academic_terms = q(
        """
        SELECT DISTINCT at.id, at.name, at.academic_year, at.term_number,
               at.starts_on::text AS starts_on, at.ends_on::text AS ends_on, at.status::text AS status
        FROM academic_terms at
        JOIN course_offerings co ON co.academic_term_id = at.id
        WHERE co.id = ANY(%s)
        ORDER BY starts_on, at.id
        """,
        [offering_ids],
    )
    sections = q(
        """
        SELECT DISTINCT s.id, s.academic_term_id, s.code
        FROM sections s
        JOIN course_offerings co ON co.section_id = s.id
        WHERE co.id = ANY(%s)
        ORDER BY s.code, s.id
        """,
        [offering_ids],
    )
    courses = q(
        """
        SELECT DISTINCT c.id, c.code, c.name
        FROM courses c
        JOIN course_offerings co ON co.course_id = c.id
        WHERE co.id = ANY(%s)
        ORDER BY c.code, c.id
        """,
        [offering_ids],
    )
    course_offerings = q(
        """
        SELECT id, course_id, academic_term_id, section_id
        FROM course_offerings
        WHERE id = ANY(%s)
        ORDER BY id
        """,
        [offering_ids],
    )
    faculty = q(
        """
        SELECT DISTINCT f.id, f.employee_code, f.institutional_email, f.display_name
        FROM faculty f
        JOIN faculty_assignments fa ON fa.faculty_id = f.id
        WHERE fa.course_offering_id = ANY(%s)
        ORDER BY f.display_name, f.id
        """,
        [offering_ids],
    )
    faculty_assignments = q(
        """
        SELECT id, faculty_id, course_offering_id, role
        FROM faculty_assignments
        WHERE course_offering_id = ANY(%s) AND active = true
        ORDER BY course_offering_id, role, id
        """,
        [offering_ids],
    )
    timetable_entries = q(
        """
        SELECT id, course_offering_id, day_of_week, start_time::text AS start_time,
               end_time::text AS end_time, room, valid_from::text AS valid_from,
               valid_until::text AS valid_until
        FROM timetable_entries
        WHERE course_offering_id = ANY(%s) AND active = true
        ORDER BY day_of_week, start_time, id
        """,
        [offering_ids],
    )
    attendance_sessions = q(
        """
        SELECT DISTINCT sess.id, sess.course_offering_id, sess.scheduled_start,
               sess.scheduled_end, sess.state::text AS state
        FROM attendance_sessions sess
        JOIN attendance_session_roster roster ON roster.attendance_session_id = sess.id
        WHERE roster.student_id = %s
          AND sess.course_offering_id = ANY(%s)
          AND sess.state IN ('SYNCING', 'RECONCILED')
        ORDER BY sess.scheduled_start, sess.id
        """,
        [student_id, offering_ids],
    )
    attendance_records = _attendance_records(student_id, q)
    summaries = _attendance_summaries(student_id, q)

    return {
        "sync_version": 1,
        "server_time": datetime.now(UTC),
        "student": student,
        "academic_terms": academic_terms,
        "sections": sections,
        "courses": courses,
        "course_offerings": course_offerings,
        "enrollments": enrollments,
        "faculty": faculty,
        "faculty_assignments": faculty_assignments,
        "timetable_entries": timetable_entries,
        "attendance_sessions": attendance_sessions,
        "attendance_records": attendance_records,
        "attendance_summaries": summaries,
        "cursor": f"goal02:{student_id}:v1",
    }


def _empty_bootstrap(student: dict) -> dict:
    return {
        "sync_version": 1,
        "server_time": datetime.now(UTC),
        "student": student,
        "academic_terms": [],
        "sections": [],
        "courses": [],
        "course_offerings": [],
        "enrollments": [],
        "faculty": [],
        "faculty_assignments": [],
        "timetable_entries": [],
        "attendance_sessions": [],
        "attendance_records": [],
        "attendance_summaries": [],
        "cursor": f"goal02:{student['id']}:v1",
    }
