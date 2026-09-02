from __future__ import annotations

import unittest
from uuid import UUID

import psycopg
from fastapi.testclient import TestClient
from nacl.signing import SigningKey

from backend.app.config import get_settings
from backend.app.device_crypto import (
    b64url_encode,
    canonical_enrollment_payload,
    public_key_fingerprint,
)
from backend.app.main import app
from backend.app.redis_service import clear_development_state


DEV_STUDENT_ID = UUID("50000000-0000-4000-8000-000000000001")
class AdminDeviceApiTest(unittest.TestCase):
    def setUp(self) -> None:
        self.client = TestClient(app)
        clear_development_state()
        with psycopg.connect(get_settings().database_url) as conn:
            conn.execute("DELETE FROM device_replacement_requests")
            conn.execute("DELETE FROM device_challenges")
            conn.execute("UPDATE attendance_records SET device_registration_id = NULL")
            conn.execute("DELETE FROM device_registrations")
            conn.execute("DELETE FROM audit_logs")

    def _sign_in_as_ict_admin(self) -> None:
        response = self.client.post(
            "/api/v1/faculty/auth/login",
            json={"email": "ananya.sen@kiit.ac.in", "password": "ChangeMe-Dev-Only!2026"},
        )
        self.assertEqual(response.status_code, 200, response.text)

    def _enroll(self, seed_byte: int) -> dict:
        challenge = self.client.post("/api/v1/devices/enrollment/challenge").json()
        key = SigningKey(bytes([seed_byte]) * 32)
        public_key = b64url_encode(bytes(key.verify_key))
        payload = canonical_enrollment_payload(
            student_id=DEV_STUDENT_ID,
            challenge_id=UUID(challenge["challenge_id"]),
            challenge=challenge["challenge"],
            issued_at=challenge["issued_at"],
            public_key_fingerprint_value=public_key_fingerprint(public_key),
        )
        response = self.client.post(
            "/api/v1/devices/enrollment/complete",
            json={
                "challenge_id": challenge["challenge_id"],
                "public_key": public_key,
                "signature": b64url_encode(key.sign(payload).signature),
                "platform": "Android",
                "display_label": "Samsung test device",
                "device_profile": {
                    "manufacturer": "Samsung",
                    "model": "SM-S931B",
                    "os_version": "15",
                    "os_api_level": 35,
                    "is_physical_device": True,
                    "is_emulator": False,
                },
            },
        )
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    def test_admin_inventory_rejects_non_ict_faculty(self) -> None:
        login = self.client.post(
            "/api/v1/faculty/auth/login",
            json={"email": "vikram.rao@kiit.ac.in", "password": "ChangeMe-Dev-Only!2026"},
        )
        self.assertEqual(login.status_code, 200, login.text)
        response = self.client.get("/api/v1/admin/devices")
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json()["error"]["code"], "ICT_ADMIN_REQUIRED")

    def test_student_replacement_route_cannot_approve_a_switch(self) -> None:
        response = self.client.post(
            "/api/v1/devices/replacement-requests/00000000-0000-4000-8000-000000000099/approve",
            json={"note": "Attempt without the admin route."},
        )
        self.assertEqual(response.status_code, 404)

    def test_admin_inventory_and_history_show_bound_device(self) -> None:
        device = self._enroll(seed_byte=31)
        self._sign_in_as_ict_admin()
        devices = self.client.get("/api/v1/admin/devices")
        self.assertEqual(devices.status_code, 200)
        matched = next(item for item in devices.json() if item["id"] == device["id"])
        self.assertTrue(matched["device_reference"].startswith("DEV-"))
        self.assertEqual(matched["manufacturer"], "Samsung")
        self.assertEqual(matched["status"], "ACTIVE")

        history = self.client.get(
            f"/api/v1/admin/devices/{device['id']}/history"
        )
        self.assertEqual(history.status_code, 200)
        self.assertTrue(any(row["event_type"] == "DEVICE_REGISTERED" for row in history.json()))

    def test_declared_emulator_is_rejected_at_binding(self) -> None:
        challenge = self.client.post("/api/v1/devices/enrollment/challenge").json()
        key = SigningKey(bytes([34]) * 32)
        public_key = b64url_encode(bytes(key.verify_key))
        payload = canonical_enrollment_payload(
            student_id=DEV_STUDENT_ID,
            challenge_id=UUID(challenge["challenge_id"]),
            challenge=challenge["challenge"],
            issued_at=challenge["issued_at"],
            public_key_fingerprint_value=public_key_fingerprint(public_key),
        )
        response = self.client.post(
            "/api/v1/devices/enrollment/complete",
            json={
                "challenge_id": challenge["challenge_id"],
                "public_key": public_key,
                "signature": b64url_encode(key.sign(payload).signature),
                "platform": "Android",
                "device_profile": {"manufacturer": "Google", "model": "sdk_gphone", "is_physical_device": False, "is_emulator": True},
            },
        )
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json()["error"]["code"], "EMULATOR_NOT_ALLOWED")
