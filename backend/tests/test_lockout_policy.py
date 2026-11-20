from __future__ import annotations

from datetime import timedelta
import unittest

from backend.app.student_identity_service import _lockout_for


class LockoutPolicyTest(unittest.TestCase):
    def test_no_lock_before_five_failures(self) -> None:
        for failures in range(0, 5):
            self.assertIsNone(_lockout_for(failures))

    def test_lock_escalates_one_two_five_then_fifteen_minutes(self) -> None:
        self.assertEqual(_lockout_for(5), timedelta(minutes=1))
        self.assertEqual(_lockout_for(6), timedelta(minutes=2))
        self.assertEqual(_lockout_for(7), timedelta(minutes=5))
        self.assertEqual(_lockout_for(8), timedelta(minutes=15))
        self.assertEqual(_lockout_for(500), timedelta(minutes=15))


if __name__ == "__main__":
    unittest.main()
