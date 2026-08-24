class AttendanceForecast {
  const AttendanceForecast({
    required this.currentPercentage,
    required this.classesToAttendToReachThreshold,
    required this.missesAvailableBeforeBelowThreshold,
  });

  final double currentPercentage;
  final int classesToAttendToReachThreshold;
  final int missesAvailableBeforeBelowThreshold;
}

double attendancePercentage({required int present, required int absent}) {
  if (present < 0 || absent < 0) {
    throw ArgumentError('attendance counts cannot be negative');
  }
  final total = present + absent;
  if (total == 0) {
    return 0;
  }
  return double.parse(((present / total) * 100).toStringAsFixed(2));
}

AttendanceForecast forecastAttendance({
  required int present,
  required int absent,
  required double thresholdPercent,
}) {
  if (present < 0 || absent < 0) {
    throw ArgumentError('attendance counts cannot be negative');
  }
  if (thresholdPercent < 0 || thresholdPercent > 100) {
    throw ArgumentError('threshold must be between 0 and 100');
  }

  final total = present + absent;
  final threshold = thresholdPercent / 100;
  final current = attendancePercentage(present: present, absent: absent);

  int needed;
  if (threshold == 0) {
    needed = 0;
  } else if (threshold == 1) {
    needed = absent == 0 ? 0 : -1;
  } else if (total == 0) {
    needed = 1;
  } else if (present / total >= threshold) {
    needed = 0;
  } else {
    needed = ((threshold * total - present) / (1 - threshold)).ceil();
  }

  int misses;
  if (threshold == 0) {
    misses = 1000000000;
  } else if (total == 0) {
    misses = 0;
  } else {
    misses = ((present / threshold) - total).floor();
    if (misses < 0) {
      misses = 0;
    }
  }

  return AttendanceForecast(
    currentPercentage: current,
    classesToAttendToReachThreshold: needed,
    missesAvailableBeforeBelowThreshold: misses,
  );
}
