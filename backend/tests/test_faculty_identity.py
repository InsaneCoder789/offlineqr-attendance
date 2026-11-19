from __future__ import annotations

import unittest
from uuid import UUID

import psycopg
from fastapi.testclient import TestClient

from backend.app.config import get_settings
from backend.app.main import app
from backend.app.redis_service import clear_development_state


DEV_FACULTY_ID = UUID("40000000-0000-4000-8000-000000000001")
DEV_PASSWORD = "ChangeMe-Dev-Only!2026"
DEV_PASSWORD_HASH = (
    "$argon2id$v=19$m=65536,t=3,p=2$Me8ShN1hllx5BzkSSYWoQA$"
    "B5V7txNYXNDOTMtcj3xEVaELILUI0NtvXETtUz9Vbag"
)


class FacultyIdentityApiTest(unittest.TestCase):
    def setUp(self) -> None:
        clear_development_state()
        with psycopg.connect(get_settings().database_url) as conn:
            conn.execute(
                """
                UPDATE faculty_credentials
                SET password_hash=%s, must_change_password=false,
                    failed_login_count=0, locked_until=NULL, updated_at=now()
                WHERE faculty_id=%s
                """,
                [DEV_PASSWORD_HASH, DEV_FACULTY_ID],
            )
        self.client = TestClient(app)

    def _login(self) -> dict:
        response = self.client.post(
            "/api/v1/faculty/auth/login",
            json={
                "email": "ananya.sen@example.edu",
                "password": DEV_PASSWORD,
            },
        )
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    def test_temporary_password_blocks_operational_routes_until_changed(self) -> None:
        with psycopg.connect(get_settings().database_url) as conn:
            conn.execute("UPDATE faculty_credentials SET must_change_password=true WHERE faculty_id=%s", [DEV_FACULTY_ID])
        self._login()
        blocked = self.client.get("/api/v1/faculty/courses")
        self.assertEqual(blocked.status_code, 403, blocked.text)
        self.assertEqual(blocked.json()["error"]["code"], "FACULTY_PASSWORD_CHANGE_REQUIRED")
        self.assertEqual(self.client.get("/api/v1/faculty/profile").status_code, 200)

    def test_login_uses_http_only_session_and_server_profile(self) -> None:
        profile = self._login()

        self.assertEqual(profile["institutional_email"], "ananya.sen@example.edu")
        self.assertIn("offlineqr_faculty_session", self.client.cookies)
        self.assertIn("offlineqr_faculty_csrf", self.client.cookies)
        restored = self.client.get("/api/v1/faculty/profile")
        self.assertEqual(restored.status_code, 200, restored.text)
        self.assertEqual(restored.json()["id"], profile["id"])

    def test_profile_mutation_requires_csrf_and_validates_phone(self) -> None:
        self._login()
        denied = self.client.patch(
            "/api/v1/faculty/profile",
            json={"display_name": "Dr. Ananya Sen", "phone_number": "+919876543210"},
        )
        self.assertEqual(denied.status_code, 403)
        self.assertEqual(denied.json()["error"]["code"], "CSRF_VALIDATION_FAILED")

        accepted = self.client.patch(
            "/api/v1/faculty/profile",
            headers={"x-csrf-token": self.client.cookies.get("offlineqr_faculty_csrf")},
            json={"display_name": "Dr. Ananya Sen", "phone_number": "+919876543210"},
        )
        self.assertEqual(accepted.status_code, 200, accepted.text)
        self.assertEqual(accepted.json()["phone_number"], "+919876543210")

    def test_invalid_password_does_not_issue_faculty_session(self) -> None:
        response = self.client.post(
            "/api/v1/faculty/auth/login",
            json={"email": "ananya.sen@example.edu", "password": "wrong"},
        )
        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.json()["error"]["code"], "INVALID_CREDENTIALS")
        self.assertNotIn("offlineqr_faculty_session", self.client.cookies)

    def test_authenticated_faculty_receives_redis_backed_session_events(self) -> None:
        self._login()
        courses = self.client.get("/api/v1/faculty/courses")
        self.assertEqual(courses.status_code, 200, courses.text)
        started = self.client.post(
            "/api/v1/faculty/attendance-sessions/start",
            headers={"x-csrf-token": self.client.cookies.get("offlineqr_faculty_csrf")},
            json={"course_offering_id": courses.json()[0]["course_offering_id"]},
        )
        self.assertEqual(started.status_code, 200, started.text)
        with self.client.websocket_connect(
            f"/api/v1/faculty/attendance-sessions/{started.json()['id']}/events",
            headers={"origin": "http://127.0.0.1:5173"},
        ) as websocket:
            event = websocket.receive_json()
        self.assertEqual(event["type"], "SESSION_UPDATED")
        self.assertEqual(event["session_id"], started.json()["id"])

    def test_password_change_revokes_every_faculty_session(self) -> None:
        second_client = TestClient(app)
        self._login()
        second_login = second_client.post(
            "/api/v1/faculty/auth/login",
            json={"email": "ananya.sen@example.edu", "password": DEV_PASSWORD},
        )
        self.assertEqual(second_login.status_code, 200, second_login.text)

        changed = self.client.post(
            "/api/v1/faculty/auth/password",
            headers={"x-csrf-token": self.client.cookies.get("offlineqr_faculty_csrf")},
            json={
                "current_password": DEV_PASSWORD,
                "new_password": "Faculty-Secure-2026!",
            },
        )
        self.assertEqual(changed.status_code, 200, changed.text)
        self.assertNotIn("offlineqr_faculty_session", self.client.cookies)

        revoked = second_client.get("/api/v1/faculty/profile")
        self.assertEqual(revoked.status_code, 401)
        self.assertEqual(revoked.json()["error"]["code"], "FACULTY_SESSION_EXPIRED")


if __name__ == "__main__":
    unittest.main()
