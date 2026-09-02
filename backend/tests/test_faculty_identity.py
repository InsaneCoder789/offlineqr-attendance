from __future__ import annotations

import unittest

from fastapi.testclient import TestClient

from backend.app.main import app


class FacultyIdentityApiTest(unittest.TestCase):
    def setUp(self) -> None:
        self.client = TestClient(app)

    def _login(self) -> dict:
        response = self.client.post(
            "/api/v1/faculty/auth/login",
            json={
                "email": "ananya.sen@kiit.ac.in",
                "password": "ChangeMe-Dev-Only!2026",
            },
        )
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    def test_login_uses_http_only_session_and_server_profile(self) -> None:
        profile = self._login()

        self.assertEqual(profile["institutional_email"], "ananya.sen@kiit.ac.in")
        self.assertIn("kiit_faculty_session", self.client.cookies)
        self.assertIn("kiit_faculty_csrf", self.client.cookies)
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
            headers={"x-csrf-token": self.client.cookies.get("kiit_faculty_csrf")},
            json={"display_name": "Dr. Ananya Sen", "phone_number": "+919876543210"},
        )
        self.assertEqual(accepted.status_code, 200, accepted.text)
        self.assertEqual(accepted.json()["phone_number"], "+919876543210")

    def test_invalid_password_does_not_issue_faculty_session(self) -> None:
        response = self.client.post(
            "/api/v1/faculty/auth/login",
            json={"email": "ananya.sen@kiit.ac.in", "password": "wrong"},
        )
        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.json()["error"]["code"], "INVALID_CREDENTIALS")
        self.assertNotIn("kiit_faculty_session", self.client.cookies)


if __name__ == "__main__":
    unittest.main()
