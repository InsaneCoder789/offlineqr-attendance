from __future__ import annotations

import unittest
from uuid import UUID

import psycopg
from fastapi.testclient import TestClient

from backend.app.config import get_settings
from backend.app.main import app
from backend.app.redis_service import clear_development_state


DEMO_STUDENT_ID = UUID("50000000-0000-4000-8000-000000000866")
DEMO_ROLL_NUMBER = "90010001"
TEMPORARY_PASSWORD = "ChangeMe-Dev-Only!2026"
TEMPORARY_PASSWORD_HASH = (
    "$argon2id$v=19$m=65536,t=3,p=2$Me8ShN1hllx5BzkSSYWoQA$"
    "B5V7txNYXNDOTMtcj3xEVaELILUI0NtvXETtUz9Vbag"
)


class StudentIdentityApiTest(unittest.TestCase):
    def setUp(self) -> None:
        clear_development_state()
        with psycopg.connect(get_settings().database_url) as conn:
            conn.execute(
                """
                UPDATE student_credentials
                SET password_hash=%s, must_change_password=true,
                    failed_login_count=0, locked_until=NULL, updated_at=now()
                WHERE student_id=%s
                """,
                [TEMPORARY_PASSWORD_HASH, DEMO_STUDENT_ID],
            )
        self.client = TestClient(app)

    def test_student_identity_requires_authentication_and_password_change(self) -> None:
        anonymous = self.client.get("/api/v1/me")
        self.assertEqual(anonymous.status_code, 401)
        self.assertEqual(anonymous.json()["error"]["code"], "STUDENT_AUTH_REQUIRED")

        login = self.client.post(
            "/api/v1/student/auth/login",
            json={"roll_number": DEMO_ROLL_NUMBER, "password": TEMPORARY_PASSWORD},
        )
        self.assertEqual(login.status_code, 200, login.text)
        self.assertTrue(login.json()["must_change_password"])
        old_token = login.json()["access_token"]
        bearer = {"authorization": f"Bearer {old_token}"}

        blocked = self.client.get("/api/v1/sync/bootstrap", headers=bearer)
        self.assertEqual(blocked.status_code, 403)
        self.assertEqual(
            blocked.json()["error"]["code"],
            "STUDENT_PASSWORD_CHANGE_REQUIRED",
        )

        changed = self.client.post(
            "/api/v1/student/auth/password",
            headers=bearer,
            json={
                "current_password": TEMPORARY_PASSWORD,
                "new_password": "Student-Secure-2026!",
            },
        )
        self.assertEqual(changed.status_code, 200, changed.text)

        revoked = self.client.get("/api/v1/me", headers=bearer)
        self.assertEqual(revoked.status_code, 401)
        self.assertEqual(revoked.json()["error"]["code"], "STUDENT_SESSION_EXPIRED")

        relogin = self.client.post(
            "/api/v1/student/auth/login",
            json={
                "roll_number": DEMO_ROLL_NUMBER,
                "password": "Student-Secure-2026!",
            },
        )
        self.assertEqual(relogin.status_code, 200, relogin.text)
        self.assertFalse(relogin.json()["must_change_password"])

    def test_failed_logins_persist_and_lock_the_account(self) -> None:
        for _ in range(5):
            bad = self.client.post(
                "/api/v1/student/auth/login",
                json={"roll_number": DEMO_ROLL_NUMBER, "password": "wrong-password-value"},
            )
            self.assertEqual(bad.status_code, 401)
        with psycopg.connect(get_settings().database_url) as conn:
            count, locked = conn.execute(
                "SELECT failed_login_count, locked_until FROM student_credentials WHERE student_id=%s",
                [DEMO_STUDENT_ID],
            ).fetchone()
        self.assertEqual(count, 5)
        self.assertIsNotNone(locked)
        good = self.client.post(
            "/api/v1/student/auth/login",
            json={"roll_number": DEMO_ROLL_NUMBER, "password": TEMPORARY_PASSWORD},
        )
        self.assertEqual(good.status_code, 401)


if __name__ == "__main__":
    unittest.main()
