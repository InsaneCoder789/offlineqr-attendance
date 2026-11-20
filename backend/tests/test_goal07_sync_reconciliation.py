from __future__ import annotations

from datetime import UTC, timedelta
import unittest
from uuid import UUID, uuid4

import psycopg
from fastapi.testclient import TestClient
from nacl.signing import SigningKey

from backend.app.attendance_protocol import canonical_attendance_claim
from backend.app.attendance_service import qr_payload_for, start_attendance_session
from backend.app.config import get_settings
from backend.app.domain import attendance_percentage
from backend.app.device_crypto import b64url_encode, public_key_fingerprint
from backend.app.main import app
from backend.app.presence_protocol import (
    ATTENDANCE_PROOF_PROTOCOL,
    canonical_attendance_proof,
    canonical_presence_response,
)
from backend.tests.support import setUpModule, tearDownModule  # noqa: F401

DEV_STUDENT_ID = UUID("50000000-0000-4000-8000-000000000001")
class Goal07SyncReconciliationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.client = TestClient(app, headers={
            "x-student-id": "50000000-0000-4000-8000-000000000001",
            "x-faculty-id": "40000000-0000-4000-8000-000000000001",
        })
        self._clear_state()
        self.key = SigningKey(bytes([77]) * 32)
        self.public_key = b64url_encode(bytes(self.key.verify_key))
        self.device_id = uuid4()
        with psycopg.connect(get_settings().database_url) as conn:
            conn.execute(
                """
                INSERT INTO device_registrations (
                    id, student_id, public_key, public_key_algorithm,
                    key_fingerprint, platform, status, registered_at
                )
                VALUES (%s, %s, %s, 'Ed25519', %s, 'Android', 'ACTIVE', now())
                """,
                [
                    self.device_id,
                    DEV_STUDENT_ID,
                    self.public_key,
                    public_key_fingerprint(self.public_key),
                ],
            )

    def tearDown(self) -> None:
        self._clear_state()

    def test_proof_submission_is_idempotent_and_creates_present_record(self) -> None:
        submission = self._submission()

        first = self.client.post("/api/v1/attendance/proofs", json=submission)
        second = self.client.post("/api/v1/attendance/proofs", json=submission)

        self.assertEqual(first.status_code, 200, first.text)
        self.assertEqual(second.status_code, 200, second.text)
        self.assertEqual(first.json()["result"], "ACCEPTED")
        self.assertEqual(second.json()["result"], "ALREADY_ACCEPTED")
        self.assertEqual(first.json()["authoritative_status"], "PRESENT")
        self.assertEqual(first.json()["attendance_method"], "SECURE_PROOF")
        with psycopg.connect(get_settings().database_url) as conn:
            count = conn.execute(
                """
                SELECT COUNT(*) FROM attendance_records
                WHERE attendance_session_id = %s AND student_id = %s
                """,
                [submission["proof"]["session_id"], DEV_STUDENT_ID],
            ).fetchone()[0]
        self.assertEqual(count, 1)

    def test_batch_returns_per_proof_result_without_failing_all(self) -> None:
        valid = self._submission()
        invalid = {**valid, "protocol_version": "ATTENDANCE_PROOF_V0"}
        invalid["proof"] = {**valid["proof"], "proof_id": str(uuid4())}

        response = self.client.post(
            "/api/v1/attendance/proofs/batch",
            json={"proofs": [valid, invalid]},
        )

        self.assertEqual(response.status_code, 200, response.text)
        results = response.json()["results"]
        self.assertEqual(results[0]["result"], "ACCEPTED")
        self.assertEqual(results[1]["result"], "REJECTED")
        self.assertEqual(results[1]["error_code"], "UNSUPPORTED_PROTOCOL")

    def test_tampered_qr_evidence_is_rejected_before_attendance_is_written(self) -> None:
        submission = self._submission()
        submission["claim"]["qr_challenge"] = "tampered-challenge"

        response = self.client.post("/api/v1/attendance/proofs", json=submission)

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["result"], "REJECTED")
        self.assertIn(response.json()["error_code"], {"QR_TAMPERED", "INVALID_QR_SIGNATURE"})

    def test_proof_scanned_before_close_reconciles_during_sync_window(self) -> None:
        submission = self._submission()
        session_id = submission["proof"]["session_id"]
        closed = self.client.post(
            f"/api/v1/faculty/attendance-sessions/{session_id}/close",
            headers={"x-faculty-id": str(self._student_today_faculty_and_offering()[0])},
        )
        response = self.client.post("/api/v1/attendance/proofs", json=submission)
        roster = self.client.get(
            f"/api/v1/faculty/attendance-sessions/{session_id}/roster",
            headers={"x-faculty-id": str(self._student_today_faculty_and_offering()[0])},
        )

        self.assertEqual(closed.status_code, 200, closed.text)
        self.assertEqual(closed.json()["state"], "SYNCING")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["result"], "ACCEPTED")
        self.assertEqual(roster.status_code, 200, roster.text)
        student = next(
            item for item in roster.json() if item["student_id"] == str(DEV_STUDENT_ID)
        )
        self.assertEqual(student["attendance_status"], "PRESENT")
        self.assertEqual(student["attendance_method"], "SECURE_PROOF")

    def test_offline_package_reuses_prepared_session_when_connectivity_returns(self) -> None:
        faculty_id, offering_id = self._student_today_faculty_and_offering()
        prepared_response = self.client.post(
            "/api/v1/faculty/attendance-sessions/offline-package",
            headers={"x-faculty-id": str(faculty_id)},
        )
        self.assertEqual(prepared_response.status_code, 200, prepared_response.text)
        prepared = next(
            item for item in prepared_response.json()
            if item["course_offering_id"] == str(offering_id)
        )
        self.assertEqual(prepared["state"], "CREATED")
        self.assertTrue(prepared["authorization"]["session_private_key"])

        activated = self.client.post(
            "/api/v1/faculty/attendance-sessions/start",
            headers={"x-faculty-id": str(faculty_id)},
            json={"course_offering_id": str(offering_id)},
        )
        self.assertEqual(activated.status_code, 200, activated.text)
        self.assertEqual(activated.json()["id"], prepared["id"])
        self.assertEqual(activated.json()["state"], "ACTIVE")

    def test_second_claim_for_same_session_student_is_claim_conflict_without_failing_batch(self) -> None:
        first = self._submission()
        # A different claim_id (fresh claim/challenge/response/proof) for the same session + student.
        second = self._submission()
        other = self._submission()
        self.assertNotEqual(first["claim"]["claim_id"], second["claim"]["claim_id"])
        # A proof from another (still valid) student identity-free claim: reject by protocol, must not poison batch.
        bad = {**other, "protocol_version": "ATTENDANCE_PROOF_V0"}

        response = self.client.post(
            "/api/v1/attendance/proofs/batch",
            json={"proofs": [first, second, bad]},
        )

        self.assertEqual(response.status_code, 200, response.text)
        results = response.json()["results"]
        self.assertEqual(results[0]["result"], "ACCEPTED")
        self.assertEqual(results[1]["result"], "REJECTED")
        self.assertEqual(results[1]["error_code"], "CLAIM_CONFLICT")
        self.assertEqual(results[2]["result"], "REJECTED")
        self.assertEqual(results[2]["error_code"], "UNSUPPORTED_PROTOCOL")
        with psycopg.connect(get_settings().database_url) as conn:
            count = conn.execute(
                "SELECT COUNT(*) FROM attendance_records WHERE attendance_session_id = %s AND student_id = %s",
                [first["proof"]["session_id"], DEV_STUDENT_ID],
            ).fetchone()[0]
        self.assertEqual(count, 1)

    def test_faculty_attestation_does_not_overwrite_secure_proof_method(self) -> None:
        submission = self._submission()
        session_id = submission["proof"]["session_id"]
        self.assertEqual(
            self.client.post("/api/v1/attendance/proofs", json=submission).json()["attendance_method"],
            "SECURE_PROOF",
        )

        attest = self.client.post(
            f"/api/v1/faculty/attendance-sessions/{session_id}/attest",
            headers={"x-faculty-id": str(self._student_today_faculty_and_offering()[0])},
            json={"student_id": str(DEV_STUDENT_ID), "reason": "Student device failure"},
        )

        self.assertEqual(attest.status_code, 200, attest.text)
        with psycopg.connect(get_settings().database_url) as conn:
            row = conn.execute(
                """
                SELECT status::text, method::text FROM attendance_records
                WHERE attendance_session_id = %s AND student_id = %s
                """,
                [session_id, DEV_STUDENT_ID],
            ).fetchone()
        self.assertEqual(row, ("PRESENT", "SECURE_PROOF"))

    def test_finalize_marks_unproven_rostered_student_absent_and_updates_percentage(self) -> None:
        faculty_id, offering_id = self._student_today_faculty_and_offering()
        session = start_attendance_session(faculty_id, offering_id)
        before = self._course_summary(offering_id)
        headers = {"x-faculty-id": str(faculty_id)}

        closed = self.client.post(
            f"/api/v1/faculty/attendance-sessions/{session['id']}/close", headers=headers
        )
        self.assertEqual(closed.status_code, 200, closed.text)
        with psycopg.connect(get_settings().database_url) as conn:
            conn.execute(
                "UPDATE attendance_sessions SET reconcile_until = now() - interval '1 minute' WHERE id = %s",
                [session["id"]],
            )
        finalized = self.client.post(
            f"/api/v1/faculty/attendance-sessions/{session['id']}/reconcile", headers=headers
        )
        self.assertEqual(finalized.status_code, 200, finalized.text)
        self.assertEqual(finalized.json()["state"], "RECONCILED")

        with psycopg.connect(get_settings().database_url) as conn:
            row = conn.execute(
                """
                SELECT status::text, method FROM attendance_records
                WHERE attendance_session_id = %s AND student_id = %s
                """,
                [session["id"], DEV_STUDENT_ID],
            ).fetchone()
        self.assertEqual(row, ("ABSENT", None))
        after = self._course_summary(offering_id)
        self.assertEqual(after["absent"], before["absent"] + 1)
        self.assertEqual(after["present"], before["present"])
        self.assertEqual(after["percentage"], attendance_percentage(after["present"], after["absent"]))
        bootstrap = self.client.get("/api/v1/sync/bootstrap").json()
        boot_summary = next(
            item for item in bootstrap["attendance_summaries"] if item["course_id"] == after["course_id"]
        )
        self.assertEqual(boot_summary["percentage"], after["percentage"])

    def _course_summary(self, offering_id: UUID) -> dict:
        with psycopg.connect(get_settings().database_url) as conn:
            course_id = conn.execute(
                "SELECT course_id FROM course_offerings WHERE id = %s", [offering_id]
            ).fetchone()[0]
        summaries = self.client.get("/api/v1/me/attendance/summary").json()
        found = [item for item in summaries if item["course_id"] == str(course_id)]
        if found:
            return found[0]
        return {"course_id": str(course_id), "present": 0, "absent": 0, "percentage": 0.0}

    def _submission(self) -> dict:
        faculty_id, offering_id = self._student_today_faculty_and_offering()
        session = start_attendance_session(faculty_id, offering_id)
        qr = qr_payload_for(session["id"], now=session["started_at"])
        captured_at = qr["issued_at"] + timedelta(seconds=1)
        claim_created_at = captured_at
        claim_expires_at = captured_at + timedelta(seconds=60)
        claim_id = uuid4()
        claim_payload = canonical_attendance_claim(
            claim_id=claim_id,
            session_id=qr["session_id"],
            student_id=DEV_STUDENT_ID,
            device_registration_id=self.device_id,
            qr_epoch=qr["epoch"],
            qr_challenge=qr["challenge"],
            qr_issued_at=qr["issued_at"].isoformat(),
            qr_expires_at=qr["expires_at"].isoformat(),
            qr_signature=qr["signature"],
            qr_captured_at=captured_at.isoformat(),
            claim_created_at=claim_created_at.isoformat(),
            claim_expires_at=claim_expires_at.isoformat(),
        )
        claim_signature = self._sign(claim_payload)

        challenge_id = uuid4()
        response_id = uuid4()
        proof_id = uuid4()
        responded_at = captured_at + timedelta(seconds=2)
        proof_created_at = captured_at + timedelta(seconds=3)
        response_payload = canonical_presence_response(
            response_id=response_id,
            challenge_id=challenge_id,
            session_id=qr["session_id"],
            claim_id=claim_id,
            device_registration_id=self.device_id,
            presence_epoch=1,
            responded_at=responded_at.isoformat(),
            transport="QR_ASSISTED_WEBRTC_DATA_CHANNEL",
            challenge_nonce="nonce-goal07",
            host_public_key="host-public-goal07",
        )
        proof_payload = canonical_attendance_proof(
            proof_id=proof_id,
            claim_id=claim_id,
            session_id=qr["session_id"],
            student_id=DEV_STUDENT_ID,
            device_registration_id=self.device_id,
            presence_challenge_id=challenge_id,
            presence_response_id=response_id,
            proof_created_at=proof_created_at.isoformat(),
        )
        return {
            "protocol_version": ATTENDANCE_PROOF_PROTOCOL,
            "claim": {
                "claim_id": str(claim_id),
                "session_id": str(qr["session_id"]),
                "student_id": str(DEV_STUDENT_ID),
                "device_registration_id": str(self.device_id),
                "qr_epoch": qr["epoch"],
                "qr_challenge": qr["challenge"],
                "qr_issued_at": qr["issued_at"].isoformat(),
                "qr_expires_at": qr["expires_at"].isoformat(),
                "qr_signature": qr["signature"],
                "qr_captured_at": captured_at.isoformat(),
                "claim_created_at": claim_created_at.isoformat(),
                "claim_expires_at": claim_expires_at.isoformat(),
                "device_signature": claim_signature,
            },
            "challenge": {
                "challenge_id": str(challenge_id),
                "session_id": str(qr["session_id"]),
                "claim_id": str(claim_id),
                "presence_epoch": 1,
                "nonce": "nonce-goal07",
                "issued_at": captured_at.isoformat(),
                "expires_at": (captured_at + timedelta(seconds=20)).isoformat(),
                "transport": "QR_ASSISTED_WEBRTC_DATA_CHANNEL",
                "host_public_key": "host-public-goal07",
            },
            "response": {
                "response_id": str(response_id),
                "challenge_id": str(challenge_id),
                "session_id": str(qr["session_id"]),
                "claim_id": str(claim_id),
                "device_registration_id": str(self.device_id),
                "presence_epoch": 1,
                "responded_at": responded_at.isoformat(),
                "transport": "QR_ASSISTED_WEBRTC_DATA_CHANNEL",
                "challenge_nonce": "nonce-goal07",
                "host_public_key": "host-public-goal07",
                "device_signature": self._sign(response_payload),
            },
            "proof": {
                "proof_id": str(proof_id),
                "claim_id": str(claim_id),
                "session_id": str(qr["session_id"]),
                "student_id": str(DEV_STUDENT_ID),
                "device_registration_id": str(self.device_id),
                "presence_challenge_id": str(challenge_id),
                "presence_response_id": str(response_id),
                "proof_created_at": proof_created_at.isoformat(),
                "final_device_signature": self._sign(proof_payload),
            },
        }

    def _sign(self, payload: bytes) -> str:
        return b64url_encode(self.key.sign(payload).signature)

    def _student_today_faculty_and_offering(self) -> tuple[UUID, UUID]:
        from backend.app.institution_clock import institution_today

        with psycopg.connect(get_settings().database_url) as conn:
            row = conn.execute(
                """
                SELECT fa.faculty_id, te.course_offering_id
                FROM timetable_entries te
                JOIN enrollments e ON e.course_offering_id = te.course_offering_id
                JOIN faculty_assignments fa ON fa.course_offering_id = te.course_offering_id
                WHERE e.student_id = %s
                  AND te.day_of_week = %s
                  AND fa.active = true
                ORDER BY te.start_time
                LIMIT 1
                """,
                [DEV_STUDENT_ID, institution_today().isoweekday()],
            ).fetchone()
        self.assertIsNotNone(row)
        return row[0], row[1]

    def _clear_state(self) -> None:
        with psycopg.connect(get_settings().database_url) as conn:
            conn.execute("DELETE FROM attendance_proofs")
            conn.execute("DELETE FROM presence_responses")
            conn.execute("DELETE FROM presence_challenges")
            conn.execute("DELETE FROM attendance_claims")
            conn.execute("DELETE FROM attendance_records")
            conn.execute("DELETE FROM session_authorizations")
            conn.execute("DELETE FROM attendance_sessions")
            conn.execute("DELETE FROM device_replacement_requests")
            conn.execute("DELETE FROM device_challenges")
            conn.execute("DELETE FROM device_registrations")
            conn.execute("DELETE FROM audit_logs")


if __name__ == "__main__":
    unittest.main()
