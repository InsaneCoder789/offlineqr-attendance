from __future__ import annotations

import concurrent.futures
import json
from datetime import UTC, datetime
from pathlib import Path
import unittest
from uuid import UUID

import psycopg
from fastapi.testclient import TestClient
from nacl.signing import SigningKey

from backend.app.config import get_settings
from backend.app.device_crypto import (
    b64url_encode,
    canonical_enrollment_payload,
    canonical_timestamp,
    canonical_verification_payload,
    public_key_fingerprint,
    verify_signature,
)
from backend.app.main import app
from backend.app.redis_service import clear_development_state

DEV_STUDENT_ID = UUID("50000000-0000-4000-8000-000000000001")


def _signing_key(seed_byte: int) -> SigningKey:
    return SigningKey(bytes([seed_byte]) * 32)


def _public_key(signing_key: SigningKey) -> str:
    return b64url_encode(bytes(signing_key.verify_key))


def _signature(signing_key: SigningKey, payload: bytes) -> str:
    return b64url_encode(signing_key.sign(payload).signature)


class DeviceApiTest(unittest.TestCase):
    def setUp(self) -> None:
        self.client = TestClient(app, headers={"x-student-id": str(DEV_STUDENT_ID)})
        self._clear_device_state()

    def tearDown(self) -> None:
        self._clear_device_state()

    def _clear_device_state(self) -> None:
        clear_development_state()
        with psycopg.connect(get_settings().database_url) as conn:
            conn.execute("DELETE FROM device_replacement_requests")
            conn.execute("DELETE FROM device_challenges")
            conn.execute("UPDATE attendance_records SET device_registration_id = NULL")
            conn.execute("DELETE FROM device_registrations")
            conn.execute("DELETE FROM audit_logs")

    def _ict_headers(self) -> dict[str, str]:
        login = self.client.post(
            "/api/v1/faculty/auth/login",
            json={"email": "ananya.sen@kiit.ac.in", "password": "ChangeMe-Dev-Only!2026"},
        )
        self.assertEqual(login.status_code, 200, login.text)
        return {"x-csrf-token": self.client.cookies.get("kiit_faculty_csrf")}

    def test_enrollment_challenge_response_creates_active_device(self) -> None:
        device = self._enroll(seed_byte=1)

        self.assertEqual(device["status"], "ACTIVE")
        self.assertEqual(device["public_key_algorithm"], "Ed25519")
        self.assertEqual(len(device["key_fingerprint"]), 64)

    def test_enrollment_challenge_is_single_use(self) -> None:
        challenge = self.client.post("/api/v1/devices/enrollment/challenge").json()
        key = _signing_key(2)
        public_key = _public_key(key)
        signature = _signature(
            key,
            canonical_enrollment_payload(
                student_id=DEV_STUDENT_ID,
                challenge_id=UUID(challenge["challenge_id"]),
                challenge=challenge["challenge"],
                issued_at=challenge["issued_at"],
                public_key_fingerprint_value=public_key_fingerprint(public_key),
            ),
        )

        first = self._complete_enrollment(challenge, public_key, signature)
        second = self._complete_enrollment(challenge, public_key, signature)

        self.assertEqual(first.status_code, 200)
        self.assertEqual(second.status_code, 409)
        self.assertEqual(second.json()["error"]["code"], "CHALLENGE_ALREADY_USED")

    def test_invalid_signature_is_rejected(self) -> None:
        challenge = self.client.post("/api/v1/devices/enrollment/challenge").json()
        key = _signing_key(3)
        public_key = _public_key(key)

        response = self._complete_enrollment(
            challenge,
            public_key,
            "invalid-signature",
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()["error"]["code"], "INVALID_DEVICE_SIGNATURE")

    def test_second_device_is_blocked(self) -> None:
        self._enroll(seed_byte=4)
        response = self._enroll_response(seed_byte=5)

        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.json()["error"]["code"], "ACTIVE_DEVICE_EXISTS")

    def test_device_verification_and_activation_revokes_old_device(self) -> None:
        device = self._enroll(seed_byte=6)
        key = _signing_key(6)

        challenge = self.client.post(
            "/api/v1/devices/verification/challenge",
            json={"device_registration_id": device["id"]},
        ).json()
        signature = _signature(
            key,
            canonical_verification_payload(
                student_id=DEV_STUDENT_ID,
                device_registration_id=UUID(device["id"]),
                challenge_id=UUID(challenge["challenge_id"]),
                challenge=challenge["challenge"],
                issued_at=challenge["issued_at"],
                public_key_fingerprint_value=device["key_fingerprint"],
            ),
        )
        verified = self.client.post(
            "/api/v1/devices/verification/complete",
            json={
                "challenge_id": challenge["challenge_id"],
                "device_registration_id": device["id"],
                "signature": signature,
            },
        )
        self.assertEqual(verified.status_code, 200)
        self.assertTrue(verified.json()["verified"])

        replacement = self._request_replacement(seed_byte=7)
        ict_headers = self._ict_headers()
        approved = self.client.post(
            f"/api/v1/admin/device-replacements/{replacement['id']}/approve",
            json={"note": "Verified device switch for test coverage."},
            headers=ict_headers,
        )
        self.assertEqual(approved.status_code, 200, approved.text)
        activation = self.client.post(
            f"/api/v1/admin/device-replacements/{replacement['id']}/activation-qr",
            headers=ict_headers,
        )
        self.assertEqual(activation.status_code, 200, activation.text)
        consumed = self.client.post(
            "/api/v1/devices/replacement-activation/consume",
            json={"qr_payload": activation.json()["qr_payload"]},
        )
        self.assertEqual(consumed.status_code, 200, consumed.text)

        revoked = self.client.post(
            "/api/v1/devices/verification/challenge",
            json={"device_registration_id": device["id"]},
        )
        self.assertEqual(revoked.status_code, 403)
        self.assertEqual(revoked.json()["error"]["code"], "DEVICE_REVOKED")

    def test_replacement_activation_is_atomic_and_single_use(self) -> None:
        old = self._enroll(seed_byte=8)
        replacement = self._request_replacement(seed_byte=9)
        ict_headers = self._ict_headers()
        approved = self.client.post(
            f"/api/v1/admin/device-replacements/{replacement['id']}/approve",
            json={"note": "Verified device switch for test coverage."},
            headers=ict_headers,
        )

        self.assertEqual(approved.status_code, 200)
        current_before_activation = self.client.get("/api/v1/devices/current").json()
        self.assertEqual(current_before_activation["id"], old["id"])

        activation = self.client.post(
            f"/api/v1/admin/device-replacements/{replacement['id']}/activation-qr",
            headers=ict_headers,
        )
        self.assertEqual(activation.status_code, 200, activation.text)
        qr_payload = activation.json()["qr_payload"]
        consumed = self.client.post(
            "/api/v1/devices/replacement-activation/consume",
            json={"qr_payload": qr_payload},
        )
        self.assertEqual(consumed.status_code, 200, consumed.text)

        current = self.client.get("/api/v1/devices/current").json()
        self.assertNotEqual(current["id"], old["id"])
        self.assertEqual(current["status"], "ACTIVE")

        with psycopg.connect(get_settings().database_url) as conn:
            count = conn.execute(
                """
                SELECT COUNT(*) FROM device_registrations
                WHERE student_id = %s AND status = 'ACTIVE'
                """,
                [DEV_STUDENT_ID],
            ).fetchone()[0]
        self.assertEqual(count, 1)

        replay = self.client.post(
            "/api/v1/devices/replacement-activation/consume",
            json={"qr_payload": qr_payload},
        )
        self.assertEqual(replay.status_code, 409)
        self.assertEqual(
            replay.json()["error"]["code"],
            "DEVICE_ACTIVATION_ALREADY_USED",
        )

    def test_concurrent_enrollment_cannot_create_two_active_devices(self) -> None:
        def attempt(seed: int) -> int:
            client = TestClient(app, headers={"x-student-id": str(DEV_STUDENT_ID)})
            challenge = client.post("/api/v1/devices/enrollment/challenge").json()
            key = _signing_key(seed)
            public_key = _public_key(key)
            signature = _signature(
                key,
                canonical_enrollment_payload(
                    student_id=DEV_STUDENT_ID,
                    challenge_id=UUID(challenge["challenge_id"]),
                    challenge=challenge["challenge"],
                    issued_at=challenge["issued_at"],
                    public_key_fingerprint_value=public_key_fingerprint(public_key),
                ),
            )
            return client.post(
                "/api/v1/devices/enrollment/complete",
                json={
                    "challenge_id": challenge["challenge_id"],
                    "public_key": public_key,
                    "signature": signature,
                    "platform": "Android",
                    "display_label": f"Concurrent {seed}",
                },
            ).status_code

        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
            statuses = list(executor.map(attempt, [10, 11]))

        self.assertEqual(statuses.count(200), 1)
        self.assertEqual(statuses.count(409), 1)
        with psycopg.connect(get_settings().database_url) as conn:
            count = conn.execute(
                """
                SELECT COUNT(*) FROM device_registrations
                WHERE student_id = %s AND status = 'ACTIVE'
                """,
                [DEV_STUDENT_ID],
            ).fetchone()[0]
        self.assertEqual(count, 1)

    def test_audit_events_are_written(self) -> None:
        self._enroll(seed_byte=12)
        with psycopg.connect(get_settings().database_url) as conn:
            events = {
                row[0]
                for row in conn.execute(
                    "SELECT event_type FROM audit_logs WHERE actor_id = %s",
                    [DEV_STUDENT_ID],
                )
            }
        self.assertIn("DEVICE_ENROLLMENT_STARTED", events)
        self.assertIn("DEVICE_REGISTERED", events)

    def test_python_verifies_shared_crypto_vector(self) -> None:
        vector = json.loads(
            Path("shared/fixtures/device_enrollment_ed25519_vector.json").read_text()
        )
        self.assertEqual(public_key_fingerprint(vector["public_key"]), vector["key_fingerprint"])
        self.assertTrue(
            verify_signature(
                public_key_b64url=vector["public_key"],
                payload=vector["canonical_payload"].encode("utf-8"),
                signature_b64url=vector["signature"],
            )
        )
        self.assertFalse(
            verify_signature(
                public_key_b64url=vector["public_key"],
                payload=(vector["canonical_payload"] + "tampered").encode("utf-8"),
                signature_b64url=vector["signature"],
            )
        )

    def test_utc_timestamp_has_one_canonical_representation(self) -> None:
        self.assertEqual(
            canonical_timestamp(datetime(2026, 9, 1, 10, 40, 52, tzinfo=UTC)),
            "2026-09-01T10:40:52Z",
        )

    def test_challenge_exposes_the_timestamp_that_the_server_verifies(self) -> None:
        challenge = self.client.post("/api/v1/devices/enrollment/challenge").json()
        self.assertTrue(challenge["issued_at"].endswith("Z"))

    def _enroll(self, seed_byte: int) -> dict:
        response = self._enroll_response(seed_byte)
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    def _enroll_response(self, seed_byte: int):
        challenge = self.client.post("/api/v1/devices/enrollment/challenge").json()
        key = _signing_key(seed_byte)
        public_key = _public_key(key)
        signature = _signature(
            key,
            canonical_enrollment_payload(
                student_id=DEV_STUDENT_ID,
                challenge_id=UUID(challenge["challenge_id"]),
                challenge=challenge["challenge"],
                issued_at=challenge["issued_at"],
                public_key_fingerprint_value=public_key_fingerprint(public_key),
            ),
        )
        return self._complete_enrollment(challenge, public_key, signature)

    def _complete_enrollment(
        self,
        challenge: dict,
        public_key: str,
        signature: str,
        device_profile: dict | None = None,
    ):
        return self.client.post(
            "/api/v1/devices/enrollment/complete",
            json={
                "challenge_id": challenge["challenge_id"],
                "public_key": public_key,
                "signature": signature,
                "platform": "Android",
                "display_label": "Test Android Device",
                "app_instance_metadata": {"app_version": "goal03-test"},
                "device_profile": device_profile or {},
                "key_protection": "SOFTWARE_PROTECTED",
            },
        )

    def _request_replacement(self, seed_byte: int) -> dict:
        challenge = self.client.post("/api/v1/devices/replacement/challenge").json()
        key = _signing_key(seed_byte)
        public_key = _public_key(key)
        signature = _signature(
            key,
            canonical_enrollment_payload(
                student_id=DEV_STUDENT_ID,
                challenge_id=UUID(challenge["challenge_id"]),
                challenge=challenge["challenge"],
                issued_at=challenge["issued_at"],
                public_key_fingerprint_value=public_key_fingerprint(public_key),
            ),
        )
        response = self.client.post(
            "/api/v1/devices/replacement-requests",
            json={
                "challenge_id": challenge["challenge_id"],
                "public_key": public_key,
                "signature": signature,
                "platform": "Android",
                "reason": "development replacement test",
            },
        )
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()


if __name__ == "__main__":
    unittest.main()
