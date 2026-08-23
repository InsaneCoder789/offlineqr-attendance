from __future__ import annotations

from datetime import date, datetime, time, timedelta, timezone
from uuid import UUID, uuid5

import psycopg

from backend.app.config import get_settings

DEMO_ROLL = "24155866"
NS = UUID("8c7d2e8b-7501-43ea-bca4-fb23ca4c708d")
TERM_START = date(2026, 8, 3)
TODAY = date(2026, 8, 20)


def stable_uuid(*parts: object) -> UUID:
    return uuid5(NS, ":".join(str(part) for part in parts))


def combine(day: date, value: time) -> datetime:
    return datetime.combine(day, value, tzinfo=timezone.utc)


def main() -> None:
    with psycopg.connect(get_settings().database_url) as conn:
        with conn.transaction():
            student = conn.execute(
                "SELECT id FROM students WHERE roll_number = %s",
                [DEMO_ROLL],
            ).fetchone()
            if student is None:
                raise SystemExit(f"Student roll {DEMO_ROLL} not found")
            student_id = student[0]

            demo_session_ids = [
                stable_uuid("demo-session", DEMO_ROLL, index)
                for index in range(1, 200)
            ]
            conn.execute(
                "DELETE FROM attendance_records WHERE attendance_session_id = ANY(%s)",
                [demo_session_ids],
            )
            conn.execute(
                "DELETE FROM attendance_session_roster WHERE attendance_session_id = ANY(%s)",
                [demo_session_ids],
            )
            conn.execute(
                "DELETE FROM session_authorizations WHERE attendance_session_id = ANY(%s)",
                [demo_session_ids],
            )
            conn.execute(
                "DELETE FROM attendance_sessions WHERE id = ANY(%s)",
                [demo_session_ids],
            )

            entries = conn.execute(
                """
                SELECT DISTINCT ON (co.id, te.day_of_week, te.start_time)
                       co.id AS offering_id, c.code AS course_code,
                       te.day_of_week, te.start_time, te.end_time,
                       COALESCE(fa.faculty_id, (
                         SELECT id FROM faculty ORDER BY display_name LIMIT 1
                       )) AS faculty_id,
                       e.id AS enrollment_id, sec.code AS section_code,
                       c.name AS course_name, s.roll_number, s.display_name
                FROM students s
                JOIN enrollments e ON e.student_id = s.id AND e.active = true
                JOIN course_offerings co ON co.id = e.course_offering_id
                JOIN courses c ON c.id = co.course_id
                JOIN sections sec ON sec.id = co.section_id
                JOIN timetable_entries te ON te.course_offering_id = co.id
                LEFT JOIN faculty_assignments fa
                  ON fa.course_offering_id = co.id AND fa.active = true
                WHERE s.id = %s AND te.active = true
                ORDER BY co.id, te.day_of_week, te.start_time
                """,
                [student_id],
            ).fetchall()

            index = 0
            per_course = {}
            day = TERM_START
            while day <= TODAY:
                for entry in entries:
                    if day.isoweekday() != entry[2]:
                        continue
                    index += 1
                    course_code = entry[1]
                    number_for_course = per_course.get(course_code, 0) + 1
                    per_course[course_code] = number_for_course
                    session_id = stable_uuid("demo-session", DEMO_ROLL, index)
                    record_id = stable_uuid("demo-record", DEMO_ROLL, index)
                    scheduled_start = combine(day, entry[3])
                    scheduled_end = combine(day, entry[4])
                    status = _status_for(course_code, number_for_course)
                    method = "SECURE_PROOF" if status == "PRESENT" else None
                    recorded_at = scheduled_start + timedelta(minutes=4)

                    conn.execute(
                        """
                        INSERT INTO attendance_sessions (
                            id, course_offering_id, created_by_faculty_id,
                            scheduled_start, scheduled_end, started_at,
                            closed_at, state
                        )
                        VALUES (%s, %s, %s, %s, %s, %s, %s, 'CLOSED')
                        ON CONFLICT (id) DO NOTHING
                        """,
                        [
                            session_id,
                            entry[0],
                            entry[5],
                            scheduled_start,
                            scheduled_end,
                            scheduled_start,
                            scheduled_end + timedelta(minutes=5),
                        ],
                    )
                    conn.execute(
                        """
                        INSERT INTO attendance_session_roster (
                            attendance_session_id, enrollment_id, student_id,
                            course_offering_id, roll_number_snapshot,
                            student_name_snapshot, section_code_snapshot,
                            course_code_snapshot, course_name_snapshot
                        )
                        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                        ON CONFLICT DO NOTHING
                        """,
                        [
                            session_id,
                            entry[6],
                            student_id,
                            entry[0],
                            entry[9],
                            entry[10],
                            entry[7],
                            entry[1],
                            entry[8],
                        ],
                    )
                    conn.execute(
                        """
                        INSERT INTO attendance_records (
                            id, attendance_session_id, student_id, status,
                            method, technical_state, recorded_at
                        )
                        VALUES (%s, %s, %s, %s, %s, 'SERVER_VERIFIED', %s)
                        ON CONFLICT (attendance_session_id, student_id)
                        DO UPDATE SET status = excluded.status,
                                      method = excluded.method,
                                      recorded_at = excluded.recorded_at,
                                      updated_at = now()
                        """,
                        [record_id, session_id, student_id, status, method, recorded_at],
                    )
                day += timedelta(days=1)

            print(f"seeded {index} demo sessions for {DEMO_ROLL}")
            for row in conn.execute(
                """
                SELECT c.code, COUNT(*) total,
                       COUNT(*) FILTER (WHERE ar.status = 'PRESENT') present,
                       COUNT(*) FILTER (WHERE ar.status = 'ABSENT') absent
                FROM attendance_records ar
                JOIN attendance_sessions sess ON sess.id = ar.attendance_session_id
                JOIN course_offerings co ON co.id = sess.course_offering_id
                JOIN courses c ON c.id = co.course_id
                WHERE ar.student_id = %s
                GROUP BY c.code
                ORDER BY c.code
                """,
                [student_id],
            ):
                print(row)


def _status_for(course_code: str, number_for_course: int) -> str:
    absences = {
        "CN": {3},
        "CNL": set(),
        "DAA": {4},
        "DAAL": set(),
        "EE": {2},
        "IPA": {3},
        "SE": {5},
        "SVP": set(),
    }
    return "ABSENT" if number_for_course in absences.get(course_code, set()) else "PRESENT"


if __name__ == "__main__":
    main()
