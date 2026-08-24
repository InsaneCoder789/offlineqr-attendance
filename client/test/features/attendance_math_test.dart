import 'package:flutter_test/flutter_test.dart';

import 'package:client/features/attendance/attendance_math.dart';

void main() {
  test('attendance percentage avoids division by zero', () {
    expect(attendancePercentage(present: 0, absent: 0), 0);
  });

  test('attendance percentage rounds deterministically', () {
    expect(attendancePercentage(present: 2, absent: 1), 66.67);
  });

  test('forecast computes classes needed to reach threshold', () {
    final forecast = forecastAttendance(
      present: 22,
      absent: 8,
      thresholdPercent: 75,
    );

    expect(forecast.currentPercentage, 73.33);
    expect(forecast.classesToAttendToReachThreshold, 2);
  });

  test('forecast computes available misses before dropping below threshold',
      () {
    final forecast = forecastAttendance(
      present: 30,
      absent: 4,
      thresholdPercent: 75,
    );

    expect(forecast.currentPercentage, 88.24);
    expect(forecast.missesAvailableBeforeBelowThreshold, 6);
  });

  test('100 percent threshold is impossible if already absent', () {
    final forecast = forecastAttendance(
      present: 2,
      absent: 1,
      thresholdPercent: 100,
    );

    expect(forecast.classesToAttendToReachThreshold, -1);
  });
}
