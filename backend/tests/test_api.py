from pathlib import Path
import unittest

from fastapi.testclient import TestClient

from backend.app.main import app
from backend.app.schemas import BootstrapSyncOut


class BootstrapApiTest(unittest.TestCase):
    def setUp(self) -> None:
        self.client = TestClient(app, headers={"x-student-id": "50000000-0000-4000-8000-000000000001"})

    def test_me_uses_development_student(self) -> None:
        response = self.client.get("/api/v1/me")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["roll_number"], "DEV24155001")

    def test_bootstrap_sync_contract(self) -> None:
        response = self.client.get("/api/v1/sync/bootstrap")
        self.assertEqual(response.status_code, 200)
        payload = response.json()

        self.assertEqual(payload["sync_version"], 1)
        self.assertEqual(payload["student"]["roll_number"], "DEV24155001")
        self.assertGreaterEqual(len(payload["courses"]), 4)
        self.assertEqual(len(payload["attendance_records"]), 4)
        self.assertEqual(len(payload["attendance_summaries"]), 2)
        self.assertTrue(payload["cursor"].startswith("goal02:"))

        exposed_rolls = {
            payload["student"]["roll_number"],
        }
        self.assertEqual(exposed_rolls, {"DEV24155001"})

    def test_dev_login_resolves_kiit_email_to_student_projection(self) -> None:
        response = self.client.post(
            "/api/v1/auth/dev-login",
            json={"email": "dev24155001@kiit.ac.in"},
        )

        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["student"]["roll_number"], "DEV24155001")
        self.assertGreater(len(response.json()["enrollments"]), 0)

    def test_absent_record_has_no_method(self) -> None:
        payload = self.client.get("/api/v1/sync/bootstrap").json()
        absent_records = [
            record
            for record in payload["attendance_records"]
            if record["status"] == "ABSENT"
        ]
        self.assertEqual(len(absent_records), 1)
        self.assertTrue(all(record["method"] is None for record in absent_records))

    def test_student_read_endpoints_are_authorized_projection(self) -> None:
        enrollments = self.client.get("/api/v1/me/enrollments")
        attendance = self.client.get("/api/v1/me/attendance")
        summary = self.client.get("/api/v1/me/attendance/summary")

        self.assertEqual(enrollments.status_code, 200)
        self.assertEqual(attendance.status_code, 200)
        self.assertEqual(summary.status_code, 200)
        self.assertGreaterEqual(len(enrollments.json()), 4)
        self.assertEqual(len(attendance.json()), 4)
        summaries = {item["course_code"]: item for item in summary.json()}
        self.assertEqual(set(summaries), {"CN", "DAA"})
        self.assertEqual(summaries["CN"]["percentage"], 100.0)
        self.assertEqual(summaries["DAA"]["percentage"], 66.67)

    def test_python_validates_shared_bootstrap_fixture(self) -> None:
        fixture_path = Path("shared/fixtures/bootstrap_dev_student.json")
        payload = BootstrapSyncOut.model_validate_json(fixture_path.read_text())

        self.assertEqual(payload.sync_version, 1)
        self.assertEqual(payload.student.roll_number, "DEV24155001")
        self.assertEqual(payload.attendance_summaries[0].percentage, 66.67)


if __name__ == "__main__":
    unittest.main()
