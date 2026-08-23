from __future__ import annotations

from uuid import UUID, uuid5

import psycopg

from backend.app.config import get_settings

DEFAULT_DEV_FACULTY_ID = UUID("40000000-0000-4000-8000-000000000001")
NS = UUID("8c7d2e8b-7501-43ea-bca4-fb23ca4c708d")


def stable_uuid(*parts: object) -> UUID:
    return uuid5(NS, ":".join(str(part) for part in parts))


def main() -> None:
    with psycopg.connect(get_settings().database_url) as conn:
        with conn.transaction():
            offerings = conn.execute(
                """
                SELECT co.id, c.code, c.name, sec.code
                FROM course_offerings co
                JOIN courses c ON c.id = co.course_id
                JOIN sections sec ON sec.id = co.section_id
                WHERE sec.code = 'CS21'
                  AND c.code IN ('CN', 'CNL', 'DAA', 'DAAL', 'EE', 'SE')
                ORDER BY c.code
                """,
            ).fetchall()
            if not offerings:
                raise SystemExit("No CS21 course offerings found. Import the KIIT timetable first.")

            for offering_id, course_code, course_name, section_code in offerings:
                assignment_id = stable_uuid(
                    "demo-faculty-assignment",
                    DEFAULT_DEV_FACULTY_ID,
                    offering_id,
                )
                conn.execute(
                    """
                    INSERT INTO faculty_assignments (id, faculty_id, course_offering_id, role, active)
                    VALUES (%s, %s, %s, 'PRIMARY', true)
                    ON CONFLICT (id) DO UPDATE
                    SET active = true,
                        role = excluded.role,
                        updated_at = now()
                    """,
                    [assignment_id, DEFAULT_DEV_FACULTY_ID, offering_id],
                )
                print(f"assigned {course_code} {section_code} - {course_name}")


if __name__ == "__main__":
    main()
