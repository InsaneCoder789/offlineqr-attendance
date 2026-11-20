import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'core/sync/bootstrap_models.dart';
import 'ui/dark_kit.dart';
import 'ui/dark_kit_extra_b.dart';
import 'ui/product_components.dart';
import 'ui/product_theme.dart';
import 'ui/state_views.dart';

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OfflineQR',
      debugShowCheckedModeBanner: false,
      theme: buildProductTheme(),
      home: const WebAttendanceDashboard(),
    );
  }
}

class WebAttendanceDashboard extends StatefulWidget {
  const WebAttendanceDashboard({super.key});

  @override
  State<WebAttendanceDashboard> createState() => _WebAttendanceDashboardState();
}

class _WebAttendanceDashboardState extends State<WebAttendanceDashboard> {
  BootstrapSyncPayload? payload;
  Map<String, dynamic>? device;
  String? error;
  bool loading = false;

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      const configuredApiBaseUrl = String.fromEnvironment('API_BASE_URL');
      final baseUri = Uri.parse(
        configuredApiBaseUrl.isEmpty
            ? 'http://127.0.0.1:8000'
            : configuredApiBaseUrl,
      );
      final bootstrapResponse =
          await http.get(baseUri.resolve('/api/v1/sync/bootstrap'));
      if (bootstrapResponse.statusCode != 200) {
        throw StateError('bootstrap failed: ${bootstrapResponse.statusCode}');
      }
      final deviceResponse =
          await http.get(baseUri.resolve('/api/v1/devices/current'));
      setState(() {
        payload = BootstrapSyncPayload.fromJson(
          jsonDecode(bootstrapResponse.body) as Map<String, dynamic>,
        );
        device = deviceResponse.statusCode == 200 &&
                deviceResponse.body.trim() != 'null'
            ? jsonDecode(deviceResponse.body) as Map<String, dynamic>
            : null;
      });
    } catch (exception) {
      setState(() => error = exception.toString());
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  Widget build(BuildContext context) {
    final current = payload;
    return Scaffold(
      appBar: AppBar(
        title: const ProductLogo(height: 34),
        actions: [
          TextButton(
            onPressed: loading ? null : load,
            child: Text(loading ? 'Loading' : 'Refresh'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: current == null
                ? _LoadingState(loading: loading, error: error, onRetry: load)
                : _WebDashboardContent(payload: current, device: device),
          ),
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState({
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: ProductSpacing.x4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(
                  child: GlowMark(size: 96, child: ProductLogo(height: 48))),
              const SizedBox(height: ProductSpacing.x6),
              if (loading)
                const StateView.loading(compact: true)
              else if (error != null)
                StateView.error(
                  title: 'Could not load data',
                  message: error!,
                  actionLabel: 'Retry',
                  onAction: onRetry,
                )
              else
                StateView.empty(
                  title: 'Backend data is not loaded yet.',
                  message: 'Load it to see courses, attendance and timetable.',
                  icon: Icons.cloud_download_outlined,
                  actionLabel: 'Retry',
                  onAction: onRetry,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WebDashboardContent extends StatelessWidget {
  const _WebDashboardContent({required this.payload, required this.device});

  final BootstrapSyncPayload payload;
  final Map<String, dynamic>? device;

  @override
  Widget build(BuildContext context) {
    final coursesById = {
      for (final course in payload.courses) course.id: course
    };
    final sectionsById = {
      for (final section in payload.sections) section.id: section
    };
    final offeringsById = {
      for (final offering in payload.courseOfferings) offering.id: offering
    };
    final sessionsById = {
      for (final session in payload.attendanceSessions) session.id: session
    };
    final summaries = <String, _CourseWebSummary>{};
    for (final record in payload.attendanceRecords) {
      final session = sessionsById[record.attendanceSessionId];
      final offering =
          session == null ? null : offeringsById[session.courseOfferingId];
      final course = offering == null ? null : coursesById[offering.courseId];
      if (course == null) continue;
      final section = sectionsById[offering!.sectionId];
      final previous = summaries[course.id] ??
          _CourseWebSummary(
            code: course.code,
            name: course.name,
            section: section?.code ?? 'Assigned',
          );
      summaries[course.id] = previous.add(record.status);
    }
    for (final enrollment in payload.enrollments) {
      final offering = offeringsById[enrollment.courseOfferingId];
      final course = offering == null ? null : coursesById[offering.courseId];
      if (course == null || summaries.containsKey(course.id)) continue;
      final section = sectionsById[offering!.sectionId];
      summaries[course.id] = _CourseWebSummary(
        code: course.code,
        name: course.name,
        section: section?.code ?? 'Assigned',
      );
    }
    final courseSummaries = summaries.values.toList()
      ..sort((left, right) => left.code.compareTo(right.code));
    final todayEntries = payload.timetableEntries
        .where((entry) => entry.dayOfWeek == DateTime.now().weekday)
        .toList()
      ..sort((left, right) => left.startTime.compareTo(right.startTime));

    return ListView(
      children: [
        NeonHero(
          padding: const EdgeInsets.all(ProductSpacing.x5),
          child: Row(
            children: [
              const Flexible(flex: 0, child: ProductLogo(height: 42)),
              const SizedBox(width: ProductSpacing.x4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      payload.student.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: ProductSpacing.x1),
                    Text(
                      payload.student.rollNumber,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: ProductSpacing.x5),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Metric(label: 'Courses', value: payload.courses.length.toString()),
            _Metric(
              label: 'Attendance Records',
              value: payload.attendanceRecords.length.toString(),
            ),
            _Metric(
              label: 'Device',
              value: device == null
                  ? 'Not registered'
                  : device!['status'] as String,
            ),
          ],
        ),
        const SizedBox(height: ProductSpacing.x6),
        Row(
          children: [
            Expanded(
              child: Text(
                'Course Summary',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            StatusChip(
              label: '${payload.enrollments.length} enrollments',
              tone: StatusTone.info,
            ),
          ],
        ),
        const SizedBox(height: ProductSpacing.x3),
        if (courseSummaries.isEmpty)
          const EmptyState(
            title: 'No enrolled courses',
            message: 'Course allocation will appear here after sync.',
            icon: Icons.school_outlined,
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: courseSummaries.length,
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 300,
              mainAxisExtent: MediaQuery.textScalerOf(context)
                  .scale(172)
                  .clamp(172.0, 420.0),
              crossAxisSpacing: ProductSpacing.x3,
              mainAxisSpacing: ProductSpacing.x3,
            ),
            itemBuilder: (context, index) => _CourseSummaryCard(
              summary: courseSummaries[index],
            ),
          ),
        const SizedBox(height: ProductSpacing.x6),
        Text('Today\'s Timetable',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: ProductSpacing.x3),
        if (todayEntries.isEmpty)
          const EmptyState(
            title: 'No class today',
            message: 'Your next scheduled class will appear after sync.',
            icon: Icons.event_available_outlined,
          )
        else
          for (final entry in todayEntries)
            Padding(
              padding: const EdgeInsets.only(bottom: ProductSpacing.x2),
              child: _TimetableRow(
                entry: entry,
                offering: offeringsById[entry.courseOfferingId],
                coursesById: coursesById,
                sectionsById: sectionsById,
              ),
            ),
        const SizedBox(height: ProductSpacing.x6),
        Text('Recent History', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: ProductSpacing.x3),
        if (payload.attendanceRecords.isEmpty)
          const EmptyState(
            title: 'No attendance captured yet',
            message: 'Verified and offline-captured records will appear here.',
            icon: Icons.fact_check_outlined,
          )
        else
          for (final record in payload.attendanceRecords.reversed.take(6))
            Padding(
              padding: const EdgeInsets.only(bottom: ProductSpacing.x2),
              child: ProductCard(
                padding: const EdgeInsets.all(ProductSpacing.x3),
                child: Row(
                  children: [
                    Expanded(
                        child: Text(record.recordedAt,
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: ProductSpacing.x2),
                    StatusChip(
                      label: record.status,
                      tone: record.status == 'PRESENT'
                          ? StatusTone.success
                          : StatusTone.error,
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

class _CourseSummaryCard extends StatelessWidget {
  const _CourseSummaryCard({required this.summary});

  final _CourseWebSummary summary;

  @override
  Widget build(BuildContext context) {
    final hasRecords = summary.total > 0;
    return ProductCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  summary.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: ProductSpacing.x2),
              Flexible(
                  flex: 0,
                  child: StatusChip(
                      label: summary.code, tone: StatusTone.neutral)),
            ],
          ),
          const SizedBox(height: ProductSpacing.x2),
          Text(summary.section,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium),
          const Spacer(),
          AttendanceProgress(percentage: summary.percentage),
          const SizedBox(height: ProductSpacing.x3),
          Text(
            hasRecords
                ? '${summary.present} / ${summary.total} present · ${summary.percentage.toStringAsFixed(1)}%'
                : 'Awaiting first attendance record',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _TimetableRow extends StatelessWidget {
  const _TimetableRow({
    required this.entry,
    required this.offering,
    required this.coursesById,
    required this.sectionsById,
  });

  final TimetableEntryDto entry;
  final CourseOfferingDto? offering;
  final Map<String, CourseDto> coursesById;
  final Map<String, SectionDto> sectionsById;

  @override
  Widget build(BuildContext context) {
    final course = offering == null ? null : coursesById[offering!.courseId];
    final section = offering == null ? null : sectionsById[offering!.sectionId];
    final time = '${_clock(entry.startTime)} - ${_clock(entry.endTime)}';
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          course?.name ?? 'Scheduled class',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: ProductSpacing.x1),
        Text(
          [
            if (course != null) course.code,
            if (section != null) section.code,
            entry.room,
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
    return ProductCard(
      padding: const EdgeInsets.all(ProductSpacing.x3),
      child: LayoutBuilder(
        builder: (context, c) {
          final timeText =
              Text(time, style: Theme.of(context).textTheme.labelLarge);
          if (c.maxWidth < 360) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                timeText,
                const SizedBox(height: ProductSpacing.x1),
                details
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 116, child: timeText),
              Expanded(child: details),
            ],
          );
        },
      ),
    );
  }

  static String _clock(String value) =>
      value.length >= 5 ? value.substring(0, 5) : value;
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 140, maxWidth: 220),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        radius: 22,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Text(value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(letterSpacing: -0.5)),
          ],
        ),
      ),
    );
  }
}

class _CourseWebSummary {
  const _CourseWebSummary({
    required this.code,
    required this.name,
    required this.section,
    this.present = 0,
    this.absent = 0,
  });

  final String code;
  final String name;
  final String section;
  final int present;
  final int absent;

  int get total => present + absent;

  double get percentage => total == 0 ? 0 : (present / total) * 100;

  _CourseWebSummary add(String status) {
    return _CourseWebSummary(
      code: code,
      name: name,
      section: section,
      present: present + (status == 'PRESENT' ? 1 : 0),
      absent: absent + (status == 'ABSENT' ? 1 : 0),
    );
  }
}
