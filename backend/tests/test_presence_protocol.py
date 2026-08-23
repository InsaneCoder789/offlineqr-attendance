from __future__ import annotations

import json
import unittest
from pathlib import Path
from uuid import UUID

from backend.app.device_crypto import verify_signature
from backend.app.presence_protocol import (
    canonical_attendance_proof,
    canonical_presence_challenge,
    canonical_presence_response,
)


class PresenceProtocolTest(unittest.TestCase):
    def setUp(self) -> None:
        self.vector = json.loads(Path("shared/fixtures/presence_v1_vector.json").read_text())

    def test_python_matches_shared_presence_vector(self) -> None:
        challenge = self.vector["challenge"]
        response = self.vector["response"]
        proof = self.vector["proof"]

        self.assertEqual(
            canonical_presence_challenge(**self._uuid_fields(challenge)).decode(),
            self.vector["canonical_presence_challenge"],
        )
        self.assertEqual(
            canonical_presence_response(**self._uuid_fields(response)).decode(),
            self.vector["canonical_presence_response"],
        )
        self.assertEqual(
            canonical_attendance_proof(**self._uuid_fields(proof)).decode(),
            self.vector["canonical_attendance_proof"],
        )
        self.assertTrue(
            verify_signature(
                public_key_b64url=self.vector["public_key"],
                payload=self.vector["canonical_presence_response"].encode(),
                signature_b64url=self.vector["presence_response_signature"],
            )
        )
        self.assertTrue(
            verify_signature(
                public_key_b64url=self.vector["public_key"],
                payload=self.vector["canonical_attendance_proof"].encode(),
                signature_b64url=self.vector["attendance_proof_signature"],
            )
        )

    def _uuid_fields(self, payload: dict) -> dict:
        return {
            key: UUID(value)
            if key.endswith("_id") or key in {"session_id", "claim_id", "student_id", "device_registration_id"}
            else value
            for key, value in payload.items()
        }


if __name__ == "__main__":
    unittest.main()
