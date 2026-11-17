from __future__ import annotations

import unittest

from pydantic import ValidationError

from backend.app.attendance_schemas import AttendanceProofBatchIn


class Phase0RegressionTest(unittest.TestCase):
    def test_proof_batch_is_capped_at_fifty(self) -> None:
        with self.assertRaises(ValidationError):
            AttendanceProofBatchIn.model_validate({"proofs": [{}] * 51})


if __name__ == "__main__":
    unittest.main()
