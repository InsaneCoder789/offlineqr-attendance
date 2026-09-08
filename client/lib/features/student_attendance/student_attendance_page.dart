import 'package:flutter/material.dart';

import '../../core/database/local_database.dart';
import '../../ui/kiit_components.dart';
import '../../ui/kiit_theme.dart';

class StudentAttendancePage extends StatelessWidget {
  const StudentAttendancePage({super.key, required this.database});

  final LocalAttendanceDatabase database;

  @override
  Widget build(BuildContext context) {
    final student = database.getCurrentStudent();
    final summaries = database.getCourseSummaries();
    final forecast = database.getOverallForecast();

    if (student == null) {
      return const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(KiitSpacing.x4),
          child: Center(
            child: EmptyState(
              title: 'Attendance data unavailable',
              message:
                  'Perform a sync to fetch and save your attendance history locally.',
              icon: Icons.cloud_sync_outlined,
            ),
          ),
        ),
      );
    }

    final present = summaries.fold<int>(0, (sum, item) => sum + item.present);
    final absent = summaries.fold<int>(0, (sum, item) => sum + item.absent);
    final total = present + absent;
    final overall = total == 0 ? 0.0 : (present / total) * 100;
    final isBelowThreshold = overall < 75.0;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(KiitSpacing.x4),
          children: [
            _StudentAttendanceHeader(student: student),
            const SizedBox(height: KiitSpacing.x5),

            // Overall Attendance Summary Card
            _OverallAttendanceCard(
              percentage: overall,
              present: present,
              total: total,
            ),
            const SizedBox(height: KiitSpacing.x4),

            if (isBelowThreshold) ...[
              _ForecastBanner(
                forecastText: _forecastText(forecast),
              ),
              const SizedBox(height: KiitSpacing.x6),
            ] else
              const SizedBox(height: KiitSpacing.x4),

            // Courses Heading
            Wrap(
              spacing: KiitSpacing.x2,
              runSpacing: KiitSpacing.x1,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Course breakdown',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: KiitColors.textPrimary,
                      ),
                ),
                StatusChip(
                  label: '${summaries.length} courses',
                  tone: StatusTone.neutral,
                ),
              ],
            ),
            const SizedBox(height: KiitSpacing.x3),

            // Subject Cards
            if (summaries.isEmpty)
              const EmptyState(
                title: 'No attendance records',
                message:
                    'Your course attendance history will appear here once sync completed.',
                icon: Icons.assignment_outlined,
              )
            else
              ...summaries.map((summary) => _CourseSummaryCard(
                    summary: summary,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SubjectAttendanceDetailPage(
                            database: database,
                            courseCode: summary.courseCode,
                          ),
                        ),
                      );
                    },
                  )),
          ],
        ),
      ),
    );
  }

  String _forecastText(dynamic forecast) {
    final needed = forecast.classesToAttendToReachThreshold as int;
    if (needed == 0) {
      final misses = forecast.missesAvailableBeforeBelowThreshold as int;
      if (misses == 0) {
        return 'You are on the boundary. Do not miss the next class.';
      }
      final noun = misses == 1 ? 'class' : 'classes';
      return 'You can safely miss the next $misses $noun without dropping below 75%.';
    }
    final noun = needed == 1 ? 'class' : 'classes';
    return 'You must attend the next $needed $noun consecutively to restore 75% attendance.';
  }
}

class _StudentAttendanceHeader extends StatelessWidget {
  const _StudentAttendanceHeader({required this.student});

  final StudentProfile student;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: KiitColors.brandPrimarySoft,
          child: Text(
            student.displayName.isNotEmpty
                ? student.displayName[0].toUpperCase()
                : 'S',
            style: const TextStyle(
              color: KiitColors.brandPrimaryStrong,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ),
        const SizedBox(width: KiitSpacing.x3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                student.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: KiitColors.textPrimary,
                    ),
              ),
              const SizedBox(height: KiitSpacing.x1),
              Text(
                'Roll: ${student.rollNumber} | Section: ${student.sectionCode}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: KiitColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OverallAttendanceCard extends StatelessWidget {
  const _OverallAttendanceCard({
    required this.percentage,
    required this.present,
    required this.total,
  });

  final double percentage;
  final int present;
  final int total;

  @override
  Widget build(BuildContext context) {
    final isHealthy = percentage >= 75.0;
    final color = isHealthy ? KiitColors.present : KiitColors.absent;

    return Container(
      decoration: BoxDecoration(
        color: KiitColors.surface,
        borderRadius: BorderRadius.circular(KiitRadius.large),
        border: Border.all(color: KiitColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(KiitSpacing.x4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 420;
          final meter = _AttendanceMeter(
            color: color,
            isHealthy: isHealthy,
            percentage: percentage,
          );
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'OVERALL ATTENDANCE',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: KiitColors.textMuted,
                      letterSpacing: 1.0,
                    ),
              ),
              const SizedBox(height: KiitSpacing.x2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '${percentage.toStringAsFixed(1)}%',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: color,
                        height: 1.0,
                      ),
                ),
              ),
              const SizedBox(height: KiitSpacing.x3),
              Text(
                '$present of $total conducted classes',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: KiitColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                details,
                const SizedBox(height: KiitSpacing.x4),
                Align(alignment: Alignment.centerLeft, child: meter),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: details),
              const SizedBox(width: KiitSpacing.x3),
              meter,
            ],
          );
        },
      ),
    );
  }
}

class _AttendanceMeter extends StatelessWidget {
  const _AttendanceMeter({
    required this.color,
    required this.isHealthy,
    required this.percentage,
  });

  final Color color;
  final bool isHealthy;
  final double percentage;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 72,
          height: 72,
          child: CircularProgressIndicator(
            value: (percentage / 100).clamp(0.0, 1.0),
            strokeWidth: 7,
            backgroundColor: KiitColors.border.withValues(alpha: 0.5),
            color: color,
            strokeCap: StrokeCap.round,
          ),
        ),
        Icon(
          isHealthy ? Icons.verified : Icons.warning_amber_rounded,
          color: color,
          size: 26,
        ),
      ],
    );
  }
}

class _ForecastBanner extends StatelessWidget {
  const _ForecastBanner({
    required this.forecastText,
  });

  final String forecastText;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0ED),
        borderRadius: BorderRadius.circular(KiitRadius.medium),
        border: Border.all(color: const Color(0xFFFECDCA)),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: KiitSpacing.x4, vertical: KiitSpacing.x3),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: KiitColors.error,
            size: 20,
          ),
          const SizedBox(width: KiitSpacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Attendance threshold warning',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: KiitColors.error,
                  ),
                ),
                const SizedBox(height: KiitSpacing.x1),
                Text(
                  forecastText,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFB42318),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CourseSummaryCard extends StatelessWidget {
  const _CourseSummaryCard({required this.summary, required this.onTap});

  final CourseSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isHealthy = summary.percentage >= 75.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: KiitSpacing.x3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(KiitRadius.large),
          child: Container(
            decoration: BoxDecoration(
              color: KiitColors.surface,
              borderRadius: BorderRadius.circular(KiitRadius.large),
              border: Border.all(color: KiitColors.border),
            ),
            padding: const EdgeInsets.all(KiitSpacing.x4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Code & Status Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      summary.courseCode,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: KiitColors.textMuted,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    StatusChip(
                      label: '${summary.percentage.toStringAsFixed(0)}%',
                      tone: isHealthy ? StatusTone.success : StatusTone.error,
                    ),
                  ],
                ),
                const SizedBox(height: KiitSpacing.x2),

                // Course Name
                Text(
                  summary.courseName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: KiitColors.textPrimary,
                        fontSize: 16,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: KiitSpacing.x3),

                // Progress Indicator
                AttendanceProgress(percentage: summary.percentage, height: 6),
                const SizedBox(height: KiitSpacing.x3),

                // Metrics Chips
                Wrap(
                  spacing: KiitSpacing.x2,
                  runSpacing: KiitSpacing.x2,
                  children: [
                    _SmallMetricChip(
                      label: '${summary.present} Present',
                      active: true,
                      isGreen: true,
                    ),
                    _SmallMetricChip(
                      label: '${summary.absent} Absent',
                      active: summary.absent > 0,
                      isGreen: false,
                    ),
                    _SmallMetricChip(
                      label: '${summary.totalClasses} Classes',
                      active: false,
                      isGreen: false,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallMetricChip extends StatelessWidget {
  const _SmallMetricChip({
    required this.label,
    required this.active,
    required this.isGreen,
  });

  final String label;
  final bool active;
  final bool isGreen;

  @override
  Widget build(BuildContext context) {
    Color bg = const Color(0xFFF1F5F3);
    Color text = KiitColors.textSecondary;

    if (active) {
      if (isGreen) {
        bg = const Color(0xFFEAF7EE);
        text = KiitColors.success;
      } else {
        bg = const Color(0xFFFFF0ED);
        text = KiitColors.error;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: KiitSpacing.x2, vertical: KiitSpacing.x1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(KiitRadius.small),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: text,
        ),
      ),
    );
  }
}

class SubjectAttendanceDetailPage extends StatelessWidget {
  const SubjectAttendanceDetailPage({
    super.key,
    required this.database,
    required this.courseCode,
  });

  final LocalAttendanceDatabase database;
  final String courseCode;

  @override
  Widget build(BuildContext context) {
    final detail = database.getCourseAttendanceDetail(courseCode);

    if (detail == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(
          child: Text('Course details not found.'),
        ),
      );
    }

    final isHealthy = detail.percentage >= 75.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(detail.courseCode),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Course Card
            Container(
              color: KiitColors.surface,
              width: double.infinity,
              padding: const EdgeInsets.all(KiitSpacing.x4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    detail.courseName,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: KiitColors.textPrimary,
                        ),
                  ),
                  const SizedBox(height: KiitSpacing.x4),
                  Row(
                    children: [
                      // Large Percentage Circular Circle
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 68,
                            height: 68,
                            child: CircularProgressIndicator(
                              value: (detail.percentage / 100).clamp(0.0, 1.0),
                              strokeWidth: 6,
                              backgroundColor:
                                  KiitColors.border.withValues(alpha: 0.5),
                              color: isHealthy
                                  ? KiitColors.present
                                  : KiitColors.absent,
                              strokeCap: StrokeCap.round,
                            ),
                          ),
                          Text(
                            '${detail.percentage.toStringAsFixed(0)}%',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: KiitColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: KiitSpacing.x5),

                      // Metrics Cards Block
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _DetailPageMetric(
                              label: 'Present',
                              value: detail.present,
                              color: KiitColors.success,
                            ),
                            _DetailPageMetric(
                              label: 'Absent',
                              value: detail.absent,
                              color: KiitColors.error,
                            ),
                            _DetailPageMetric(
                              label: 'Conducted',
                              value: detail.present + detail.absent,
                              color: KiitColors.textPrimary,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // History Header
            Container(
              width: double.infinity,
              color: KiitColors.background,
              padding: const EdgeInsets.symmetric(
                  horizontal: KiitSpacing.x4, vertical: KiitSpacing.x3),
              child: Text(
                'ATTENDANCE LOG',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: KiitColors.textMuted,
                      letterSpacing: 1.0,
                    ),
              ),
            ),

            // History Timeline list
            Expanded(
              child: detail.history.isEmpty
                  ? const Center(
                      child: EmptyState(
                        title: 'No classes logged',
                        message:
                            'Sync to retrieve the attendance details of this subject.',
                        icon: Icons.history_outlined,
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: KiitSpacing.x4, vertical: KiitSpacing.x2),
                      itemCount: detail.history.length,
                      itemBuilder: (context, index) {
                        final item = detail.history[index];
                        final isPresent = item.status == 'PRESENT';
                        final isLast = index == detail.history.length - 1;

                        return _HistoryTimelineRow(
                          item: item,
                          isPresent: isPresent,
                          isLast: isLast,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailPageMetric extends StatelessWidget {
  const _DetailPageMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value.toString(),
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        const SizedBox(height: KiitSpacing.x1),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: KiitColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _HistoryTimelineRow extends StatelessWidget {
  const _HistoryTimelineRow({
    required this.item,
    required this.isPresent,
    required this.isLast,
  });

  final AttendanceHistoryItem item;
  final bool isPresent;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final statusColor = isPresent ? KiitColors.success : KiitColors.error;
    final statusBg =
        isPresent ? const Color(0xFFEAF7EE) : const Color(0xFFFFF0ED);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline Indicator
          SizedBox(
            width: 32,
            child: Column(
              children: [
                const SizedBox(height: KiitSpacing.x3),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2.0),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2.0,
                    color: isLast ? Colors.transparent : KiitColors.border,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: KiitSpacing.x2),

          // Detail Row Content Card
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: KiitSpacing.x2),
              child: Container(
                decoration: BoxDecoration(
                  color: KiitColors.surface,
                  borderRadius: BorderRadius.circular(KiitRadius.medium),
                  border: Border.all(color: KiitColors.border),
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: KiitSpacing.x3, vertical: KiitSpacing.x2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _dateOnly(item.scheduledStart),
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: KiitColors.textPrimary,
                                    fontSize: 14,
                                  ),
                        ),
                        const SizedBox(height: KiitSpacing.x1),
                        Text(
                          item.method ?? 'Auto System Log',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: KiitColors.textMuted,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: KiitSpacing.x2, vertical: KiitSpacing.x1),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(KiitRadius.small),
                      ),
                      child: Text(
                        isPresent ? 'PRESENT' : 'ABSENT',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: statusColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _dateOnly(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${parsed.day} ${months[parsed.month - 1]} ${parsed.year}';
  }
}
