from __future__ import annotations

import unittest
from datetime import timedelta
from uuid import UUID

from fastapi.testclient import TestClient

from backend.app.attendance_protocol import (
    QR_EPOCH_SECONDS,
    canonical_attendance_qr,
    canonical_session_authorization,
    verify,
)
from backend.app.attendance_service import qr_payload_for, start_attendance_session
from backend.app.main import app

DEV_FACULTY_ID = UUID("40000000-0000-4000-8000-000000000001")


class Goal04AttendanceApiTest(unittest.TestCase):
    def setUp(self) -> None:
        self.client = TestClient(app)

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
        self.assertEqual(close.json()["state"], "CLOSED")
        self.assertEqual(qr.status_code, 409)
        self.assertEqual(qr.json()["error"]["code"], "SESSION_CLOSED")

    def _today_offering_id(self) -> str:
        response = self.client.get("/api/v1/faculty/classes/today")
        self.assertEqual(response.status_code, 200)
        classes = response.json()
        self.assertTrue(classes)
        return classes[0]["course_offering_id"]

    def _unauthorized_offering_id(self) -> str:
        response = self.client.get("/api/v1/sync/bootstrap")
        self.assertEqual(response.status_code, 200)
        student_offerings = {
            item["id"] for item in response.json()["course_offerings"]
        }
        faculty_offerings = {
            row["course_offering_id"]
            for row in self.client.get("/api/v1/faculty/classes/today").json()
        }
        unauthorized = sorted(student_offerings - faculty_offerings)
        self.assertTrue(unauthorized)
        return unauthorized[0]


if __name__ == "__main__":
    unittest.main()
