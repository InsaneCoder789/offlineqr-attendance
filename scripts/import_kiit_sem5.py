from __future__ import annotations

import argparse
import os
import re
import zipfile
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from xml.etree import ElementTree as ET
from uuid import UUID, uuid5

import psycopg


NAMESPACE = UUID("0cf90000-0000-4000-8000-000000000005")
DEV_STUDENT_ID = UUID("50000000-0000-4000-8000-000000000001")
DEV_FACULTY_ID = UUID("40000000-0000-4000-8000-000000000001")
TERM_ID = UUID("10000000-0000-4000-8000-000000000005")

DAY_TO_ISO = {
    "monday": 1,
    "tuesday": 2,
    "wednesday": 3,
    "thursday": 4,
    "friday": 5,
    "saturday": 6,
    "sunday": 7,
}

COURSE_NAMES = {
    "AI": "Artificial Intelligence",
    "BD": "Big Data",
    "BDS": "Big Data Systems",
    "CD": "Compiler Design",
    "CI": "Computational Intelligence",
    "CN": "Computer Networks",
    "CNL": "Computer Networks Laboratory",
    "DAA": "Design and Analysis of Algorithms",
    "DAAL": "Design and Analysis of Algorithms Laboratory",
    "DMDW": "Data Mining and Data Warehousing",
    "DOS": "Distributed Operating Systems",
    "DSA": "Data Structures and Algorithms",
    "EE": "Engineering Economics",
    "HPC": "High Performance Computing",
    "IPA": "Image Processing and Analysis",
    "MLC": "Machine Learning Concepts",
    "NIC": "Network and Information Security",
    "OB": "Organizational Behaviour",
    "PSIOT": "Privacy and Security in IoT",
    "SE": "Software Engineering",
    "SVP": "Software Verification and Validation",
}

NS = {
    "main": "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
    "rel": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
    "pkgrel": "http://schemas.openxmlformats.org/package/2006/relationships",
}


@dataclass(frozen=True)
class TimetableEntry:
    section: str
    day_of_week: int
    start_time: str
    end_time: str
    course_code: str
    faculty_name: str
    room: str


def stable_uuid(kind: str, value: str) -> UUID:
    return uuid5(NAMESPACE, f"{kind}:{value.strip().upper()}")


def clean(value: object) -> str:
    text = str(value).strip()
    if text.endswith(".0") and text.replace(".0", "").isdigit():
        text = text[:-2]
    return text.strip()


def email_slug(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", ".", value.lower()).strip(".")
    return slug or "unknown"


def parse_period(column: str) -> tuple[str, str]:
    match = re.search(r"(\d{2}):(\d{2})", column)
    if not match:
        raise ValueError(f"Could not parse period column: {column}")
    hour = int(match.group(1))
    minute = int(match.group(2))
    return f"{hour:02d}:{minute:02d}:00", f"{hour + 1:02d}:{minute:02d}:00"


def column_index(cell_ref: str) -> int:
    letters = re.match(r"([A-Z]+)", cell_ref)
    if not letters:
        return 0
    value = 0
    for char in letters.group(1):
        value = value * 26 + (ord(char) - ord("A") + 1)
    return value - 1


def shared_strings(archive: zipfile.ZipFile) -> list[str]:
    try:
        root = ET.fromstring(archive.read("xl/sharedStrings.xml"))
    except KeyError:
        return []
    values: list[str] = []
    for item in root.findall("main:si", NS):
        texts = [node.text or "" for node in item.findall(".//main:t", NS)]
        values.append("".join(texts))
    return values


def sheet_path(archive: zipfile.ZipFile, sheet_name: str) -> str:
    workbook = ET.fromstring(archive.read("xl/workbook.xml"))
    rels = ET.fromstring(archive.read("xl/_rels/workbook.xml.rels"))
    rel_targets = {
        rel.attrib["Id"]: rel.attrib["Target"]
        for rel in rels.findall("pkgrel:Relationship", NS)
    }
    for sheet in workbook.findall("main:sheets/main:sheet", NS):
        if sheet.attrib.get("name") == sheet_name:
            rel_id = sheet.attrib[f"{{{NS['rel']}}}id"]
            target = rel_targets[rel_id]
            return f"xl/{target}" if not target.startswith("/") else target[1:]
    raise ValueError(f"Sheet not found: {sheet_name}")


def cell_value(cell: ET.Element, strings: list[str]) -> str:
    cell_type = cell.attrib.get("t")
    if cell_type == "inlineStr":
        texts = [node.text or "" for node in cell.findall(".//main:t", NS)]
        return clean("".join(texts))
    value = cell.find("main:v", NS)
    if value is None or value.text is None:
        return ""
    raw = value.text
    if cell_type == "s":
        return clean(strings[int(float(raw))])
    return clean(raw)


def read_sheet(path: Path, sheet_name: str) -> list[dict[str, str]]:
    with zipfile.ZipFile(path) as archive:
        strings = shared_strings(archive)
        root = ET.fromstring(archive.read(sheet_path(archive, sheet_name)))
    rows: list[list[str]] = []
    for row in root.findall(".//main:sheetData/main:row", NS):
        values: list[str] = []
        for cell in row.findall("main:c", NS):
            index = column_index(cell.attrib.get("r", "A1"))
            while len(values) <= index:
                values.append("")
            values[index] = cell_value(cell, strings)
        rows.append(values)
    if not rows:
        return []
    headers = rows[0]
    return [
        {headers[index]: values[index] if index < len(values) else "" for index in range(len(headers)) if headers[index]}
        for values in rows[1:]
    ]


def read_allocations(path: Path) -> tuple[dict[str, str], dict[str, tuple[str, str]]]:
    core = read_sheet(path, "Core")
    elective = read_sheet(path, "Elective")

    core_sections: dict[str, str] = {}
    for row in core:
        roll = clean(row.get("Roll No"))
        section = clean(row.get("Sec"))
        if roll and section:
            core_sections[roll] = section

    elective_sections: dict[str, tuple[str, str]] = {}
    for row in elective:
        roll = clean(row.get("Roll Number"))
        pe1 = clean(row.get("PE1 Section"))
        pe2 = clean(row.get("PE2 Section"))
        if roll:
            elective_sections[roll] = (pe1, pe2)

    return core_sections, elective_sections


def read_timetable(path: Path) -> list[TimetableEntry]:
    grid = read_sheet(path, "Section Grid")
    period_columns = [column for column in grid[0] if str(column).startswith("P")] if grid else []
    entries: list[TimetableEntry] = []

    for row in grid:
        section = clean(row.get("Section"))
        day_name = clean(row.get("Day")).lower()
        if not section or section.startswith("Sem ") or "course group" in day_name:
            continue
        day = DAY_TO_ISO.get(day_name)
        if day is None:
            continue
        for column in period_columns:
            cell = clean(row.get(column))
            if not cell:
                continue
            parts = [part.strip() for part in cell.split("\n") if part.strip()]
            if len(parts) < 3:
                continue
            start_time, end_time = parse_period(str(column))
            entries.append(
                TimetableEntry(
                    section=section,
                    day_of_week=day,
                    start_time=start_time,
                    end_time=end_time,
                    course_code=parts[0],
                    faculty_name=parts[1],
                    room=parts[2],
                )
            )
    return entries


def reset_database(conn: psycopg.Connection) -> None:
    conn.execute(
        """
        TRUNCATE TABLE
            attendance_proofs,
            presence_responses,
            presence_challenges,
            device_replacement_requests,
            device_challenges,
            device_registrations,
            auth_identities,
            audit_logs,
            faculty_attestations,
            attendance_records,
            attendance_claims,
            session_authorizations,
            attendance_session_roster,
            attendance_sessions,
            enrollments,
            faculty_assignments,
            timetable_entries,
            course_offerings,
            courses,
            sections,
            students,
            faculty,
            academic_terms
        RESTART IDENTITY CASCADE
        """
    )


def choose_dev_student(core_sections: dict[str, str], elective_sections: dict[str, tuple[str, str]]) -> str:
    for roll in sorted(core_sections):
        if roll in elective_sections and core_sections[roll].startswith("CS"):
            return roll
    return sorted(core_sections)[0]


def choose_dev_faculty(entries: list[TimetableEntry]) -> str:
    today = date.today().isoweekday()
    for entry in entries:
        if entry.day_of_week == today:
            return entry.faculty_name
    return entries[0].faculty_name


def import_data(conn: psycopg.Connection, allocation_path: Path, timetable_path: Path) -> dict[str, int | str]:
    core_sections, elective_sections = read_allocations(allocation_path)
    timetable = read_timetable(timetable_path)
    dev_roll = choose_dev_student(core_sections, elective_sections)
    dev_faculty_name = choose_dev_faculty(timetable)

    section_codes = sorted(
        set(core_sections.values())
        | {section for sections in elective_sections.values() for section in sections if section}
        | {entry.section for entry in timetable}
    )
    course_codes = sorted({entry.course_code for entry in timetable})
    faculty_names = sorted({entry.faculty_name for entry in timetable})

    conn.execute(
        """
        INSERT INTO academic_terms (id, name, academic_year, term_number, starts_on, ends_on, status)
        VALUES (%s, 'Autumn 2026 - Semester 5', '2026-27', 5, '2026-08-01', '2026-12-20', 'ACTIVE')
        """,
        [TERM_ID],
    )

    for section in section_codes:
        conn.execute(
            "INSERT INTO sections (id, academic_term_id, code) VALUES (%s, %s, %s)",
            [stable_uuid("section", section), TERM_ID, section],
        )

    for code in course_codes:
        conn.execute(
            "INSERT INTO courses (id, code, name) VALUES (%s, %s, %s)",
            [stable_uuid("course", code), code, COURSE_NAMES.get(code, code)],
        )

    for name in faculty_names:
        faculty_id = DEV_FACULTY_ID if name == dev_faculty_name else stable_uuid("faculty", name)
        conn.execute(
            """
            INSERT INTO faculty (id, employee_code, institutional_email, display_name)
            VALUES (%s, %s, %s, %s)
            """,
            [
                faculty_id,
                f"SEM5-{email_slug(name)[:24].upper()}",
                f"{email_slug(name)}@kiit.ac.in",
                name,
            ],
        )

    offerings: set[tuple[str, str]] = {(entry.course_code, entry.section) for entry in timetable}
    for code, section in sorted(offerings):
        offering_id = stable_uuid("offering", f"{code}:{section}")
        conn.execute(
            """
            INSERT INTO course_offerings (id, course_id, academic_term_id, section_id)
            VALUES (%s, %s, %s, %s)
            """,
            [offering_id, stable_uuid("course", code), TERM_ID, stable_uuid("section", section)],
        )

    assigned: set[tuple[str, str, str]] = set()
    for entry in timetable:
        key = (entry.faculty_name, entry.course_code, entry.section)
        if key in assigned:
            continue
        assigned.add(key)
        conn.execute(
            """
            INSERT INTO faculty_assignments (id, faculty_id, course_offering_id, role)
            VALUES (%s, %s, %s, 'PRIMARY')
            """,
            [
                stable_uuid("faculty-assignment", ":".join(key)),
                DEV_FACULTY_ID if entry.faculty_name == dev_faculty_name else stable_uuid("faculty", entry.faculty_name),
                stable_uuid("offering", f"{entry.course_code}:{entry.section}"),
            ],
        )

    seen_timetable: set[tuple[str, int, str, str, str, str]] = set()
    for entry in timetable:
        key = (entry.section, entry.day_of_week, entry.start_time, entry.end_time, entry.course_code, entry.room)
        if key in seen_timetable:
            continue
        seen_timetable.add(key)
        conn.execute(
            """
            INSERT INTO timetable_entries (
                id, course_offering_id, day_of_week, start_time, end_time, room, valid_from, valid_until
            )
            VALUES (%s, %s, %s, %s, %s, %s, '2026-08-01', '2026-12-20')
            """,
            [
                stable_uuid("timetable", ":".join(map(str, key))),
                stable_uuid("offering", f"{entry.course_code}:{entry.section}"),
                entry.day_of_week,
                entry.start_time,
                entry.end_time,
                entry.room,
            ],
        )

    all_rolls = sorted(set(core_sections) | set(elective_sections))
    for roll in all_rolls:
        student_id = DEV_STUDENT_ID if roll == dev_roll else stable_uuid("student", roll)
        conn.execute(
            """
            INSERT INTO students (id, roll_number, institutional_email, display_name)
            VALUES (%s, %s, %s, %s)
            """,
            [student_id, roll, f"{roll}@kiit.ac.in", f"Student {roll}"],
        )

    enrollments: set[tuple[str, str, str]] = set()
    for roll, section in core_sections.items():
        for entry in timetable:
            if entry.section == section:
                enrollments.add((roll, entry.course_code, section))
    for roll, (pe1, pe2) in elective_sections.items():
        for elective_section in (pe1, pe2):
            if not elective_section:
                continue
            for entry in timetable:
                if entry.section == elective_section:
                    enrollments.add((roll, entry.course_code, elective_section))

    for roll, code, section in sorted(enrollments):
        conn.execute(
            """
            INSERT INTO enrollments (id, student_id, course_offering_id)
            VALUES (%s, %s, %s)
            ON CONFLICT (student_id, course_offering_id) DO NOTHING
            """,
            [
                stable_uuid("enrollment", f"{roll}:{code}:{section}"),
                DEV_STUDENT_ID if roll == dev_roll else stable_uuid("student", roll),
                stable_uuid("offering", f"{code}:{section}"),
            ],
        )

    return {
        "students": len(all_rolls),
        "sections": len(section_codes),
        "courses": len(course_codes),
        "faculty": len(faculty_names),
        "course_offerings": len(offerings),
        "timetable_entries": len(seen_timetable),
        "enrollments": len(enrollments),
        "dev_student_roll": dev_roll,
        "dev_faculty": dev_faculty_name,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Import KIIT Semester 5 section allocation and timetable into the dev database.")
    parser.add_argument("--allocation", type=Path, default=Path("/Users/rohanc/Downloads/Section detail_5th (1).xlsx"))
    parser.add_argument("--timetable", type=Path, default=Path("/Users/rohanc/Downloads/5th_Semester_timetable_core_elective_student.xlsx"))
    parser.add_argument("--database-url", default=os.environ.get("DATABASE_URL", "postgresql://localhost/kiit_attendance_goal02"))
    args = parser.parse_args()

    with psycopg.connect(args.database_url) as conn:
        with conn.transaction():
            reset_database(conn)
            summary = import_data(conn, args.allocation, args.timetable)

    for key, value in summary.items():
        print(f"{key}: {value}")


if __name__ == "__main__":
    main()
