from datetime import UTC, datetime
import unittest

from backend.app.institution_clock import institution_now, institution_today


class InstitutionClockTest(unittest.TestCase):
    def test_utc_evening_is_next_institution_day(self) -> None:
        instant = datetime(2026, 9, 9, 20, 0, tzinfo=UTC)

        self.assertEqual(institution_today(instant).isoformat(), "2026-09-10")
        self.assertEqual(institution_now(instant).hour, 1)

    def test_utc_morning_remains_same_institution_day(self) -> None:
        instant = datetime(2026, 9, 9, 2, 30, tzinfo=UTC)

        self.assertEqual(institution_today(instant).isoformat(), "2026-09-09")
        self.assertEqual(institution_now(instant).hour, 8)


if __name__ == "__main__":
    unittest.main()
