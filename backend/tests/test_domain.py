import unittest

from backend.app.domain import attendance_percentage, forecast_attendance


class AttendanceMathTest(unittest.TestCase):
    def test_percentage_handles_zero_total(self) -> None:
        self.assertEqual(attendance_percentage(0, 0), 0.0)

    def test_percentage_rounds(self) -> None:
        self.assertEqual(attendance_percentage(2, 1), 66.67)

    def test_forecast_classes_needed(self) -> None:
        forecast = forecast_attendance(22, 8, 75)
        self.assertEqual(forecast.current_percentage, 73.33)
        self.assertEqual(forecast.classes_to_attend_to_reach_threshold, 2)

    def test_forecast_available_misses(self) -> None:
        forecast = forecast_attendance(30, 4, 75)
        self.assertEqual(forecast.current_percentage, 88.24)
        self.assertEqual(forecast.misses_available_before_below_threshold, 6)

    def test_impossible_full_attendance_after_absence(self) -> None:
        forecast = forecast_attendance(2, 1, 100)
        self.assertEqual(forecast.classes_to_attend_to_reach_threshold, -1)


if __name__ == "__main__":
    unittest.main()

