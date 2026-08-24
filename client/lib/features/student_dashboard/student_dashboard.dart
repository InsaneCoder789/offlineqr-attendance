import 'package:flutter/material.dart';

import '../../core/database/local_database.dart';
import '../device_security/device_screen.dart';
import '../attendance/attendance_math.dart';

class StudentDashboard extends StatefulWidget {
  const StudentDashboard({
    super.key,
    required this.database,
    this.refreshToken = 0,
    this.onSync,
    this.syncing = false,
  });

  final LocalAttendanceDatabase database;
  final int refreshToken;
  final Future<void> Function()? onSync;
  final bool syncing;

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  late StudentProfile? student;
  late List<CourseSummary> summaries;
  late List<AttendanceHistoryItem> history;
  late AttendanceForecast forecast;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant StudentDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      setState(_load);
    }
  }

  void _load() {
    student = widget.database.getCurrentStudent();
    summaries = widget.database.getCourseSummaries();
    history = widget.database.getAttendanceHistory();
    forecast = widget.database.getOverallForecast();
  }

  @override
  Widget build(BuildContext context) {
    if (student == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Attendance')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('No local attendance data synced yet.'),
              const SizedBox(height: 16),
              if (widget.onSync != null)
                FilledButton(
                  onPressed: widget.syncing ? null : widget.onSync,
                  child: Text(widget.syncing ? 'Syncing' : 'Sync'),
                ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance'),
        actions: [
          if (widget.onSync != null)
            TextButton(
              onPressed: widget.syncing ? null : widget.onSync,
              child: Text(widget.syncing ? 'Syncing' : 'Sync'),
            ),
          IconButton(
            tooltip: 'Attendance Device',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DeviceScreen(database: widget.database),
                ),
              );
            },
            icon: const Icon(Icons.phonelink_lock),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            student!.displayName,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text('${student!.rollNumber} · ${student!.sectionCode}'),
          const SizedBox(height: 24),
          Text('Courses', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final summary in summaries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${summary.courseCode} · ${summary.courseName}'),
              subtitle: Text(
                '${summary.present} / ${summary.totalClasses} present',
              ),
              trailing: Text('${summary.percentage.toStringAsFixed(2)}%'),
            ),
          const SizedBox(height: 24),
          Text('Forecast', style: Theme.of(context).textTheme.titleMedium),
          Text(
            forecast.classesToAttendToReachThreshold == 0
                ? 'You are at or above 75%.'
                : 'Attend the next ${forecast.classesToAttendToReachThreshold} classes to reach 75%.',
          ),
          Text(
            'Misses available before dropping below 75%: '
            '${forecast.missesAvailableBeforeBelowThreshold}',
          ),
          const SizedBox(height: 24),
          Text('History', style: Theme.of(context).textTheme.titleMedium),
          for (final item in history)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${item.courseCode} · ${item.status}'),
              subtitle: Text(item.scheduledStart),
              trailing: Text(item.method ?? 'ABSENCE'),
            ),
        ],
      ),
    );
  }
}
