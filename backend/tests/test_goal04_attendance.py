from __future__ import annotations

import unittest
from datetime import timedelta
from uuid import UUID

import psycopg
from fastapi.testclient import TestClient

from backend.app.attendance_protocol import (
    QR_EPOCH_SECONDS,
    canonical_attendance_qr,
    canonical_session_authorization,
    verify,
)
from backend.app.attendance_service import qr_payload_for, start_attendance_session
from backend.app.config import get_settings
from backend.app.main import app
from backend.tests.support import setUpModule, tearDownModule  # noqa: F401

DEV_FACULTY_ID = UUID("40000000-0000-4000-8000-000000000001")


class Goal04AttendanceApiTest(unittest.TestCase):
    def setUp(self) -> None:
        self.client = TestClient(app, headers={"x-faculty-id": str(DEV_FACULTY_ID)})

    def test_faculty_sees_only_assigned_today_classes(self) -> None:
        response = self.client.get("/api/v1/faculty/classes/today")

        self.assertEqual(response.status_code, 200)
        self.assertGreater(len(response.json()), 0)
        self.assertTrue(all(row["section_code"] for row in response.json()))

    def test_faculty_report_endpoints_are_authorized_and_academic(self) -> None:
        courses = self.client.get("/api/v1/faculty/courses")
        self.assertEqual(courses.status_code, 200)
        self.assertGreater(len(courses.json()), 0)

        sessions = self.client.get("/api/v1/faculty/attendance-sessions?limit=5")
        self.assertEqual(sessions.status_code, 200)
        self.assertLessEqual(len(sessions.json()), 5)

        offering_id = courses.json()[0]["course_offering_id"]
        register = self.client.get(
            f"/api/v1/faculty/course-offerings/{offering_id}/register"
        )
        self.assertEqual(register.status_code, 200, register.text)
        payload = register.json()
        self.assertEqual(payload["course_offering_id"], offering_id)
        self.assertIn("students", payload)
        self.assertIn("sessions", payload)
        if payload["students"]:
            self.assertNotIn("device_registration_id", payload["students"][0])

        unauthorized = self._unauthorized_offering_id()
        blocked = self.client.get(
            f"/api/v1/faculty/course-offerings/{unauthorized}/register"
        )
        self.assertEqual(blocked.status_code, 403)
        self.assertEqual(blocked.json()["error"]["code"], "FACULTY_NOT_AUTHORIZED")

    def test_start_session_requires_faculty_assignment(self) -> None:
        unauthorized = self._unauthorized_offering_id()
        response = self.client.post(
            "/api/v1/faculty/attendance-sessions/start",
            json={"course_offering_id": unauthorized},
        )

        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json()["error"]["code"], "FACULTY_NOT_AUTHORIZED")

    def test_start_session_snapshots_roster_and_issues_authorization(self) -> None:
        offering_id = self._today_offering_id()
        response = self.client.post(
            "/api/v1/faculty/attendance-sessions/start",
            json={"course_offering_id": offering_id},
        )

        self.assertEqual(response.status_code, 200, response.text)
        session = response.json()
        self.assertEqual(session["state"], "ACTIVE")
        self.assertIsNotNone(session["authorization"])
        roster = self.client.get(
            f"/api/v1/faculty/attendance-sessions/{session['id']}/roster"
        )
        self.assertEqual(roster.status_code, 200)
        self.assertGreaterEqual(len(roster.json()), 8)

    def test_qr_payload_verifies_against_session_authorization(self) -> None:
        session = start_attendance_session(DEV_FACULTY_ID, UUID(self._today_offering_id()))
        qr = qr_payload_for(session["id"], now=session["started_at"])
        auth = qr["session_authorization"]

        auth_payload = canonical_session_authorization(
            authorization_id=auth["authorization_id"],
            session_id=auth["session_id"],
            course_offering_id=auth["course_offering_id"],
            faculty_id=auth["faculty_id"],
            valid_from=auth["valid_from"].isoformat(),
            valid_until=auth["valid_until"].isoformat(),
            key_id=auth["key_id"],
            session_public_key=auth["session_public_key"],
        )
        self.assertTrue(
            verify(
                self.client.get("/api/v1/trust-roots/current").json()["public_key"],
                auth_payload,
                auth["server_signature"],
            )
        )
        qr_payload = canonical_attendance_qr(
            session_id=qr["session_id"],
            epoch=qr["epoch"],
            issued_at=qr["issued_at"].isoformat(),
            expires_at=qr["expires_at"].isoformat(),
            challenge=qr["challenge"],
            key_id=qr["key_id"],
        )
        self.assertTrue(verify(auth["session_public_key"], qr_payload, qr["signature"]))

    def test_qr_epoch_changes_every_five_seconds(self) -> None:
        session = start_attendance_session(DEV_FACULTY_ID, UUID(self._today_offering_id()))
        first = qr_payload_for(session["id"], now=session["started_at"])
        second = qr_payload_for(
            session["id"],
            now=session["started_at"] + timedelta(seconds=QR_EPOCH_SECONDS),
        )

        self.assertEqual(first["epoch"] + 1, second["epoch"])
        self.assertNotEqual(first["signature"], second["signature"])

    def test_faculty_attestation_records_present_without_new_status(self) -> None:
        offering_id = self._today_offering_id()
        session = self.client.post(
            "/api/v1/faculty/attendance-sessions/start",
            json={"course_offering_id": offering_id},
        ).json()
        roster = self.client.get(
            f"/api/v1/faculty/attendance-sessions/{session['id']}/roster"
        ).json()
        response = self.client.post(
            f"/api/v1/faculty/attendance-sessions/{session['id']}/attest",
            json={
                "student_id": roster[0]["student_id"],
                "reason": "Student device failure",
            },
        )

        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["status"], "PRESENT")
        self.assertEqual(response.json()["method"], "FACULTY_ATTESTATION")

    def test_close_session_stops_qr_generation(self) -> None:
        offering_id = self._today_offering_id()
        session = self.client.post(
            "/api/v1/faculty/attendance-sessions/start",
            json={"course_offering_id": offering_id},
        ).json()

        close = self.client.post(
            f"/api/v1/faculty/attendance-sessions/{session['id']}/close"
        )
        qr = self.client.get(f"/api/v1/faculty/attendance-sessions/{session['id']}/qr")

        self.assertEqual(close.status_code, 200)
        self.assertEqual(close.json()["state"], "SYNCING")
        self.assertEqual(qr.status_code, 409)
        self.assertEqual(qr.json()["error"]["code"], "SESSION_CLOSED")

    def test_qr_payload_requires_the_assigned_faculty_session(self) -> None:
        offering_id = self._today_offering_id()
        session = self.client.post(
            "/api/v1/faculty/attendance-sessions/start",
            json={"course_offering_id": offering_id},
        ).json()

        anonymous = TestClient(app).get(
            f"/api/v1/faculty/attendance-sessions/{session['id']}/qr"
        )

        self.assertEqual(anonymous.status_code, 401)
        self.assertEqual(anonymous.json()["error"]["code"], "FACULTY_AUTH_REQUIRED")

    def test_course_with_several_slots_prepares_and_starts_each_slot(self) -> None:
        from datetime import time
        from uuid import uuid4

        from backend.app.institution_clock import institution_local_to_utc, institution_today

        offering_id = self._today_offering_id()
        today = institution_today()
        slot_id = uuid4()
        with psycopg.connect(get_settings().database_url) as conn:
            conn.execute(
                """
                INSERT INTO timetable_entries (id, course_offering_id, day_of_week, start_time, end_time, room, valid_from, valid_until)
                SELECT %s, course_offering_id, day_of_week, '23:10', '23:50', 'X-1', valid_from, valid_until
                FROM timetable_entries WHERE course_offering_id = %s AND day_of_week = %s LIMIT 1
                """,
                [slot_id, offering_id, today.isoweekday()],
            )
        try:
            prepared = self.client.post("/api/v1/faculty/attendance-sessions/offline-package")
            self.assertEqual(prepared.status_code, 200, prepared.text)
            mine = [item for item in prepared.json() if item["course_offering_id"] == offering_id]
            self.assertEqual(len(mine), 2)
            self.assertEqual(len({item["id"] for item in mine}), 2)

            started = self.client.post(
                "/api/v1/faculty/attendance-sessions/start",
                json={"course_offering_id": offering_id, "timetable_entry_id": str(slot_id)},
            )
            self.assertEqual(started.status_code, 200, started.text)
            self.assertIn(started.json()["id"], {item["id"] for item in mine})
            with psycopg.connect(get_settings().database_url) as conn:
                start = conn.execute(
                    "SELECT scheduled_start FROM attendance_sessions WHERE id = %s",
                    [started.json()["id"]],
                ).fetchone()[0]
            self.assertEqual(start, institution_local_to_utc(today, time(23, 10)))

            missing = self.client.post(
                "/api/v1/faculty/attendance-sessions/start",
                json={"course_offering_id": offering_id, "timetable_entry_id": str(uuid4())},
            )
            self.assertEqual(missing.status_code, 404)
            self.assertEqual(missing.json()["error"]["code"], "TIMETABLE_ENTRY_NOT_FOUND")
        finally:
            with psycopg.connect(get_settings().database_url) as conn:
                conn.execute("DELETE FROM timetable_entries WHERE id = %s", [slot_id])

    def _today_offering_id(self) -> str:
        response = self.client.get("/api/v1/faculty/classes/today")
        self.assertEqual(response.status_code, 200)
        classes = response.json()
        self.assertTrue(classes)
        return classes[0]["course_offering_id"]

    def _unauthorized_offering_id(self) -> str:
        with psycopg.connect(get_settings().database_url) as conn:
            row = conn.execute(
                """
                SELECT co.id
                FROM course_offerings co
                WHERE NOT EXISTS (
                    SELECT 1 FROM faculty_assignments fa
                    WHERE fa.course_offering_id = co.id
                      AND fa.faculty_id = %s
                      AND fa.active = true
                )
                ORDER BY co.id
                LIMIT 1
                """,
                [DEV_FACULTY_ID],
            ).fetchone()
        self.assertIsNotNone(row)
        return str(row[0])


if __name__ == "__main__":
    unittest.main()
