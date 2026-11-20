import 'package:flutter/material.dart';

import '../../core/database/local_database.dart';
import '../attendance/attendance_math.dart';
import '../../ui/dark_kit.dart';
import '../../ui/dark_kit_extra_a.dart';
import '../../ui/product_theme.dart';
import '../../ui/responsive.dart';
import '../../ui/state_views.dart';

const double _threshold = 75.0;

Color _toneFor(double pct) =>
    pct >= _threshold ? ProductColors.present : ProductColors.absent;

double _textScale(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(14) / 14;

/// Attendance overview: compact overall hero, one-line forecast, and the
/// courses (sortable). Scrolls as a whole, so nothing can overflow.
///
/// Every non-happy path is a first-class state: loading skeleton, no student
/// synced, no courses, database error with retry and an optional stale strip.
class StudentAttendancePage extends StatefulWidget {
  const StudentAttendancePage(
      {super.key, required this.database, this.staleNotice});

  final LocalAttendanceDatabase database;

  /// When non-null a slim warning strip is shown above the content, for
  /// example "Offline. Last synced 2 days ago."
  final String? staleNotice;

  @override
  State<StudentAttendancePage> createState() => _StudentAttendancePageState();
}

enum _Sort { lowestFirst, alphabetical }

class _AttendanceData {
  const _AttendanceData(
      {required this.student,
      required this.summaries,
      required this.forecastText});

  final StudentProfile? student;
  final List<CourseSummary> summaries;
  final String forecastText;
}

class _StudentAttendancePageState extends State<StudentAttendancePage> {
  _AttendanceData? _data;
  bool _loading = false;
  Object? _error;
  _Sort _sort = _Sort.lowestFirst;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant StudentAttendancePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.database != widget.database) _load();
  }

  void _load() {
    try {
      final student = widget.database.getCurrentStudent();
      final summaries = widget.database.getCourseSummaries();
      final present = summaries.fold<int>(0, (s, i) => s + i.present);
      final absent = summaries.fold<int>(0, (s, i) => s + i.absent);
      final total = present + absent;
      final overall = total == 0 ? 0.0 : present / total * 100;
      _data = _AttendanceData(
        student: student,
        summaries: summaries,
        forecastText:
            _forecastText(widget.database.getOverallForecast(), overall, total),
      );
      _error = null;
    } catch (error) {
      _error = error;
    }
    _loading = false;
  }

  Future<void> _retry() async {
    setState(() => _loading = true);
    // One frame of skeleton so the retry is visibly doing something.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    setState(_load);
  }

  Future<void> _refresh() async {
    setState(_load);
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final Widget body;
    if (_loading) {
      body = const AdaptivePage(children: [AttendanceLoadingView()]);
    } else if (_error != null || data == null) {
      body = AdaptivePage(children: [
        const SizedBox(height: ProductSpacing.x10),
        StateView.error(
          title: 'Could not read attendance',
          message:
              'Your saved data is safe on this phone. Try again in a moment.',
          onAction: _retry,
        ),
      ]);
    } else if (data.student == null) {
      body = AdaptivePage(children: [
        if (widget.staleNotice != null) ..._stale(),
        const SizedBox(height: ProductSpacing.x10),
        const StateView.empty(
          icon: Icons.cloud_sync_outlined,
          title: 'Attendance data unavailable',
          message:
              'No student is synced to this phone yet. Sign in and sync once to save your attendance history here.',
        ),
      ]);
    } else {
      body = _content(context, data, data.student!);
    }
    return Scaffold(body: SafeArea(child: body));
  }

  List<Widget> _stale() => [
        const SizedBox(height: ProductSpacing.x4),
        StatusStrip(message: widget.staleNotice!),
      ];

  Widget _content(
      BuildContext context, _AttendanceData data, StudentProfile student) {
    final text = Theme.of(context).textTheme;
    final summaries = [...data.summaries];
    if (_sort == _Sort.lowestFirst) {
      summaries.sort((a, b) {
        final c = a.percentage.compareTo(b.percentage);
        return c != 0 ? c : a.courseCode.compareTo(b.courseCode);
      });
    } else {
      summaries.sort((a, b) =>
          a.courseName.toLowerCase().compareTo(b.courseName.toLowerCase()));
    }
    final present = summaries.fold<int>(0, (s, i) => s + i.present);
    final absent = summaries.fold<int>(0, (s, i) => s + i.absent);
    final total = present + absent;
    final overall = total == 0 ? 0.0 : present / total * 100;

    return AdaptivePage(
      onRefresh: _refresh,
      children: [
        if (widget.staleNotice != null) ..._stale(),
        _Identity(student: student),
        const SizedBox(height: ProductSpacing.x4),
        _OverallCard(
          percentage: overall,
          present: present,
          total: total,
          forecast: data.forecastText,
          hasData: total > 0,
        ),
        const SizedBox(height: ProductSpacing.x5),
        Wrap(
          spacing: ProductSpacing.x3,
          runSpacing: ProductSpacing.x2,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Wrap(
              spacing: ProductSpacing.x2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Courses',
                    style: text.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800, letterSpacing: -0.6)),
                Text('${summaries.length}', style: text.bodyMedium),
              ],
            ),
            if (summaries.length > 1)
              _SortToggle(
                  value: _sort, onChanged: (v) => setState(() => _sort = v)),
          ],
        ),
        const SizedBox(height: ProductSpacing.x3),
        if (summaries.isEmpty)
          const StateView.empty(
            icon: Icons.assignment_outlined,
            title: 'No attendance records yet',
            message:
                'Course attendance appears here once your first sync completes.',
          )
        else
          LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth >= 560 ? 2 : 1;
            final w = (c.maxWidth - (cols - 1) * ProductSpacing.x3) / cols;
            return Wrap(
              spacing: ProductSpacing.x3,
              runSpacing: ProductSpacing.x3,
              children: [
                for (var i = 0; i < summaries.length; i++)
                  SizedBox(
                    width: w,
                    child: i < 10
                        ? Reveal(
                            index: i, child: _courseCard(context, summaries[i]))
                        : _courseCard(context, summaries[i]),
                  ),
              ],
            );
          }),
      ],
    );
  }

  Widget _courseCard(BuildContext context, CourseSummary summary) {
    return _CourseCard(
      summary: summary,
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => SubjectAttendanceDetailPage(
            database: widget.database, courseCode: summary.courseCode),
      )),
    );
  }
}

String _forecastText(AttendanceForecast f, double overall, int total) {
  if (total == 0) {
    return 'Your forecast appears after your first classes are recorded.';
  }
  final needed = f.classesToAttendToReachThreshold;
  if (needed < 0) {
    return 'Attendance is below 75% and cannot be restored by attending alone.';
  }
  if (needed == 0) {
    final misses = f.missesAvailableBeforeBelowThreshold;
    if (misses == 0) {
      return 'You are right on the 75% line. Do not miss the next class.';
    }
    return 'You can miss ${misses == 1 ? '1 class' : '$misses classes'} and stay above 75%.';
  }
  return 'Attend the next $needed ${needed == 1 ? 'class' : 'classes'} in a row to get back to 75%.';
}

/// Loading skeleton shaped like the real attendance screen.
class AttendanceLoadingView extends StatelessWidget {
  const AttendanceLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading attendance',
      child: const ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: ProductSpacing.x4),
            Row(
              children: [
                SkeletonBox(height: 52, width: 52, radius: 26),
                SizedBox(width: ProductSpacing.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(height: 18, width: 160),
                      SizedBox(height: 8),
                      SkeletonBox(height: 12, width: 110),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: ProductSpacing.x4),
            GlassCard(
              radius: 28,
              child: Row(
                children: [
                  SkeletonBox(height: 112, width: 112, radius: 56),
                  SizedBox(width: ProductSpacing.x4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(height: 12, width: 90),
                        SizedBox(height: 10),
                        SkeletonBox(height: 20),
                        SizedBox(height: 10),
                        SkeletonBox(height: 24, width: 96, radius: 12),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: ProductSpacing.x5),
            SkeletonBox(height: 24, width: 120),
            SizedBox(height: ProductSpacing.x3),
            SkeletonList(rows: 3),
          ],
        ),
      ),
    );
  }
}

class _SortToggle extends StatelessWidget {
  const _SortToggle({required this.value, required this.onChanged});

  final _Sort value;
  final ValueChanged<_Sort> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: _SortOption(
                label: 'Lowest first',
                selected: value == _Sort.lowestFirst,
                onTap: () => onChanged(_Sort.lowestFirst),
              ),
            ),
            Flexible(
              child: _SortOption(
                label: 'A to Z',
                selected: value == _Sort.alphabetical,
                onTap: () => onChanged(_Sort.alphabetical),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SortOption extends StatelessWidget {
  const _SortOption(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Sort $label',
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color:
                    selected ? ProductColors.brandPrimary : Colors.transparent,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: ProductSpacing.x3, vertical: 8),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: selected
                              ? ProductColors.onBrand
                              : ProductColors.textSecondary,
                        ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Identity extends StatelessWidget {
  const _Identity({required this.student});

  final StudentProfile student;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final name = student.displayName.trim();
    return Padding(
      padding: const EdgeInsets.only(top: ProductSpacing.x3),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ProductColors.brandPrimary.withValues(alpha: 0.14),
              border: Border.all(
                  color: ProductColors.brandPrimary.withValues(alpha: 0.5)),
            ),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: Text(
                  name.isNotEmpty ? name.characters.first.toUpperCase() : 'S',
                  style: const TextStyle(
                      color: ProductColors.brandPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 20),
                ),
              ),
            ),
          ),
          const SizedBox(width: ProductSpacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(student.displayName,
                    style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800, letterSpacing: -0.3),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                Text('${student.rollNumber} · Section ${student.sectionCode}',
                    style: text.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact overall hero: ring + big % + "x of y classes" + status pill, then
/// a slim forecast line. Side by side when there is room, tightly stacked
/// otherwise. Sized so a course card is visible on a 360x640 phone.
class _OverallCard extends StatelessWidget {
  const _OverallCard({
    required this.percentage,
    required this.present,
    required this.total,
    required this.forecast,
    required this.hasData,
  });

  final double percentage;
  final int present;
  final int total;
  final String forecast;
  final bool hasData;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final ok = percentage >= _threshold;
    final tone = hasData ? _toneFor(percentage) : ProductColors.textMuted;
    final scale = _textScale(context);
    return NeonHero(
      padding: const EdgeInsets.all(ProductSpacing.x4),
      child: LayoutBuilder(builder: (context, c) {
        final inner = c.maxWidth;
        final sideBySide = inner >= 270 && scale <= 1.45;
        final ringSize = sideBySide ? (inner >= 380 ? 136.0 : 120.0) : 112.0;
        final ring = GlowRing(
          value: percentage,
          size: ringSize,
          stroke: 11,
          color: tone,
          child: Text('${percentage.toStringAsFixed(0)}%',
              style: text.displaySmall?.copyWith(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.2,
                  height: 1.0,
                  color: ProductColors.textPrimary,
                  fontFeatures: tabularFigures)),
        );
        final facts = Column(
          crossAxisAlignment:
              sideBySide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('OVERALL ATTENDANCE',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: sideBySide ? TextAlign.start : TextAlign.center,
                style: text.labelSmall?.copyWith(
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                    color: ProductColors.textSecondary)),
            const SizedBox(height: ProductSpacing.x1),
            Text('$present of $total classes',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: sideBySide ? TextAlign.start : TextAlign.center,
                style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800, fontFeatures: tabularFigures)),
            const SizedBox(height: ProductSpacing.x2),
            if (hasData)
              NeonPill(
                  label: ok ? 'On track' : 'Below 75%',
                  color: tone,
                  icon: ok
                      ? Icons.check_circle_rounded
                      : Icons.warning_amber_rounded)
            else
              const NeonPill(
                  label: 'No classes yet',
                  color: ProductColors.textMuted,
                  icon: Icons.hourglass_empty_rounded),
          ],
        );
        final forecastLine = DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(ProductRadius.medium),
            border: Border.all(color: tone.withValues(alpha: 0.3)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: ProductSpacing.x3, vertical: ProductSpacing.x2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(Icons.insights_rounded, size: 18, color: tone),
                ),
                const SizedBox(width: ProductSpacing.x2),
                Expanded(
                  child: Text(forecast,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                          color: ProductColors.textPrimary,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (sideBySide)
              Row(
                children: [
                  ring,
                  const SizedBox(width: ProductSpacing.x4),
                  Expanded(child: facts),
                ],
              )
            else ...[
              Center(child: ring),
              const SizedBox(height: ProductSpacing.x3),
              facts,
            ],
            const SizedBox(height: ProductSpacing.x3),
            forecastLine,
          ],
        );
      }),
    );
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({required this.summary, required this.onTap});

  final CourseSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final tone = _toneFor(summary.percentage);
    final accent = courseAccent(summary.courseCode);
    final low = summary.percentage < _threshold;
    return Semantics(
      container: true,
      button: true,
      label: '${summary.courseCode} ${summary.courseName}, '
          '${summary.percentage.toStringAsFixed(0)} percent, '
          '${summary.present} present, ${summary.absent} absent',
      child: ExcludeSemantics(
        child: GlassCard(
          padding: EdgeInsets.zero,
          radius: ProductRadius.large + 2,
          onTap: onTap,
          child: LayoutBuilder(builder: (context, c) {
            final compact = c.maxWidth < 260;
            return ClipRRect(
              borderRadius: BorderRadius.circular(ProductRadius.large + 2),
              child: Stack(
                children: [
                  PositionedDirectional(
                    start: 0,
                    top: 0,
                    bottom: 0,
                    width: 5,
                    child: ColoredBox(color: accent),
                  ),
                  Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(
                      5 + (compact ? ProductSpacing.x3 : ProductSpacing.x4),
                      compact ? ProductSpacing.x3 : ProductSpacing.x4,
                      compact ? ProductSpacing.x3 : ProductSpacing.x4,
                      compact ? ProductSpacing.x3 : ProductSpacing.x4,
                    ),
                    child: Row(
                      children: [
                        GlowRing(
                          value: summary.percentage,
                          size: compact ? 52 : 64,
                          stroke: 6,
                          color: tone,
                          child: Text(
                              '${summary.percentage.toStringAsFixed(0)}%',
                              style: text.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                  color: ProductColors.textPrimary,
                                  fontFeatures: tabularFigures)),
                        ),
                        SizedBox(
                            width: compact
                                ? ProductSpacing.x3
                                : ProductSpacing.x4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(summary.courseCode,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.labelMedium?.copyWith(
                                      color: accent,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.8)),
                              Text(summary.courseName,
                                  style: text.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              Text(
                                  '${summary.present} present · ${summary.absent} absent',
                                  style: text.bodyMedium,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                              if (low) ...[
                                const SizedBox(height: ProductSpacing.x1),
                                Text('Below 75%',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.labelMedium?.copyWith(
                                        color: ProductColors.absent,
                                        fontWeight: FontWeight.w800)),
                              ],
                            ],
                          ),
                        ),
                        if (!compact)
                          const Padding(
                            padding: EdgeInsetsDirectional.only(
                                start: ProductSpacing.x1),
                            child: Icon(Icons.chevron_right_rounded,
                                color: ProductColors.textMuted),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Course detail
// ---------------------------------------------------------------------------

enum _LogFilter { all, present, absent }

/// One flattened row of the month-grouped attendance log.
class _LogItem {
  const _LogItem.header(this.month, this.present, this.absent) : item = null;
  const _LogItem.row(this.item)
      : month = null,
        present = 0,
        absent = 0;

  final String? month;
  final int present;
  final int absent;
  final AttendanceHistoryItem? item;
}

const _monthShort = [
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
const _monthLong = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December'
];
const _weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Parses an ISO timestamp and shifts it to institution time (IST).
DateTime? _institutionTime(String value) {
  final p = DateTime.tryParse(value);
  if (p == null) return null;
  return p.isUtc ? p.add(const Duration(hours: 5, minutes: 30)) : p;
}

List<_LogItem> _groupByMonth(List<AttendanceHistoryItem> history) {
  final out = <_LogItem>[];
  final groups = <String, List<AttendanceHistoryItem>>{};
  for (final h in history) {
    final d = _institutionTime(h.scheduledStart);
    final key =
        d == null ? 'Unknown date' : '${_monthLong[d.month - 1]} ${d.year}';
    groups.putIfAbsent(key, () => []).add(h);
  }
  groups.forEach((month, rows) {
    final present = rows.where((r) => r.status == 'PRESENT').length;
    out.add(_LogItem.header(month, present, rows.length - present));
    out.addAll(rows.map(_LogItem.row));
  });
  return out;
}

class SubjectAttendanceDetailPage extends StatefulWidget {
  const SubjectAttendanceDetailPage(
      {super.key, required this.database, required this.courseCode});

  final LocalAttendanceDatabase database;
  final String courseCode;

  @override
  State<SubjectAttendanceDetailPage> createState() =>
      _SubjectAttendanceDetailPageState();
}

class _SubjectAttendanceDetailPageState
    extends State<SubjectAttendanceDetailPage> {
  CourseAttendanceDetail? _detail;
  Object? _error;
  _LogFilter _filter = _LogFilter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    try {
      _detail = widget.database.getCourseAttendanceDetail(widget.courseCode);
      _error = null;
    } catch (e) {
      _error = e;
    }
  }

  Widget _stateScaffold(String? title, Widget state) {
    return Scaffold(
      appBar: AppBar(
          title: title == null
              ? null
              : Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: SafeArea(
        child: AdaptivePage(
            children: [const SizedBox(height: ProductSpacing.x10), state]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    if (_error != null) {
      return _stateScaffold(
        null,
        StateView.error(
          title: 'Could not read this course',
          message:
              'Your saved data is safe on this phone. Try again in a moment.',
          onAction: () => setState(_load),
        ),
      );
    }
    if (detail == null) {
      return _stateScaffold(
        null,
        StateView.empty(
          icon: Icons.search_off_rounded,
          title: 'Course not found',
          message: 'This course is not saved on this phone.',
          actionLabel: 'Go back',
          onAction: () => Navigator.of(context).maybePop(),
        ),
      );
    }
    final text = Theme.of(context).textTheme;
    final tone = _toneFor(detail.percentage);
    final accent = courseAccent(detail.courseCode);
    final filtered = switch (_filter) {
      _LogFilter.all => detail.history,
      _LogFilter.present =>
        detail.history.where((h) => h.status == 'PRESENT').toList(),
      _LogFilter.absent =>
        detail.history.where((h) => h.status != 'PRESENT').toList(),
    };
    final items = _groupByMonth(filtered);

    return Scaffold(
      appBar: AppBar(
          title: Text(detail.courseCode,
              maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, c) {
          final base = c.maxWidth >= Breakpoints.medium
              ? ProductSpacing.x6
              : ProductSpacing.x4;
          final side = ((c.maxWidth - 640) / 2).clamp(base, double.infinity);
          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: side),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const SizedBox(height: ProductSpacing.x3),
                    Text(detail.courseName,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: text.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                            color: accent)),
                    const SizedBox(height: ProductSpacing.x3),
                    _DetailHero(detail: detail, tone: tone),
                    const SizedBox(height: ProductSpacing.x5),
                    Text('Attendance log',
                        style: text.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                    const SizedBox(height: ProductSpacing.x2),
                    if (detail.history.isNotEmpty) ...[
                      _FilterRow(
                          value: _filter,
                          onChanged: (v) => setState(() => _filter = v)),
                      const SizedBox(height: ProductSpacing.x3),
                    ],
                    if (detail.history.isEmpty)
                      const StateView.empty(
                        icon: Icons.history_outlined,
                        title: 'No classes logged',
                        message: 'Sync to load this course\'s history.',
                      )
                    else if (filtered.isEmpty)
                      const StateView.empty(
                        compact: true,
                        icon: Icons.filter_list_off_rounded,
                        title: 'Nothing matches',
                        message: 'No classes match this filter.',
                      ),
                  ]),
                ),
              ),
              if (items.isNotEmpty)
                SliverPadding(
                  padding:
                      EdgeInsets.fromLTRB(side, 0, side, ProductSpacing.x8),
                  sliver: SliverList.builder(
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final it = items[i];
                      if (it.item == null) {
                        return _MonthHeader(
                            month: it.month!,
                            present: it.present,
                            absent: it.absent);
                      }
                      return _LogRow(item: it.item!);
                    },
                  ),
                )
              else
                const SliverToBoxAdapter(
                    child: SizedBox(height: ProductSpacing.x8)),
            ],
          );
        }),
      ),
    );
  }
}

class _DetailHero extends StatelessWidget {
  const _DetailHero({required this.detail, required this.tone});

  final CourseAttendanceDetail detail;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scale = _textScale(context);
    return NeonHero(
      padding: const EdgeInsets.all(ProductSpacing.x4),
      child: LayoutBuilder(builder: (context, c) {
        final sideBySide = c.maxWidth >= 300 && scale <= 1.45;
        final ring = GlowRing(
          value: detail.percentage,
          size: sideBySide ? 128 : 116,
          stroke: 11,
          color: tone,
          child: Text('${detail.percentage.toStringAsFixed(0)}%',
              style: text.displaySmall?.copyWith(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.2,
                  height: 1.0,
                  color: ProductColors.textPrimary,
                  fontFeatures: tabularFigures)),
        );
        final metrics = Wrap(
          alignment: sideBySide ? WrapAlignment.start : WrapAlignment.center,
          runSpacing: ProductSpacing.x3,
          spacing: ProductSpacing.x5,
          children: [
            _Metric(
                label: 'Present',
                value: detail.present,
                color: ProductColors.success,
                icon: Icons.check_rounded),
            _Metric(
                label: 'Absent',
                value: detail.absent,
                color: ProductColors.error,
                icon: Icons.close_rounded),
            _Metric(
                label: 'Held',
                value: detail.present + detail.absent,
                color: ProductColors.textPrimary,
                icon: Icons.event_note_rounded),
          ],
        );
        if (sideBySide) {
          return Row(children: [
            ring,
            const SizedBox(width: ProductSpacing.x5),
            Expanded(child: metrics)
          ]);
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [ring, const SizedBox(height: ProductSpacing.x4), metrics],
        );
      }),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.value, required this.onChanged});

  final _LogFilter value;
  final ValueChanged<_LogFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, _LogFilter f) {
      final selected = value == f;
      return Semantics(
        button: true,
        selected: selected,
        label: 'Show $label',
        child: ExcludeSemantics(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(f),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: selected
                      ? ProductColors.brandPrimary.withValues(alpha: 0.16)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                      color: selected
                          ? ProductColors.brandPrimary.withValues(alpha: 0.6)
                          : Colors.white.withValues(alpha: 0.08)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: ProductSpacing.x4, vertical: 8),
                  child: Center(
                    widthFactor: 1,
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: selected
                                ? ProductColors.brandPrimary
                                : ProductColors.textSecondary)),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: ProductSpacing.x2,
      runSpacing: ProductSpacing.x2,
      children: [
        chip('All', _LogFilter.all),
        chip('Present', _LogFilter.present),
        chip('Absent', _LogFilter.absent),
      ],
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader(
      {required this.month, required this.present, required this.absent});

  final String month;
  final int present;
  final int absent;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(
          top: ProductSpacing.x4, bottom: ProductSpacing.x2),
      child: Wrap(
        spacing: ProductSpacing.x3,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Text(month.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.labelMedium?.copyWith(
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w800,
                  color: ProductColors.textSecondary)),
          Text('$present present · $absent absent',
              style: text.labelSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(
      {required this.label,
      required this.value,
      required this.color,
      required this.icon});

  final String label;
  final int value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 56, maxWidth: 120),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('$value',
                style: text.headlineMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                    letterSpacing: -1,
                    fontFeatures: tabularFigures)),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 3),
              Flexible(
                  child: Text(label,
                      style: text.labelMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)),
            ],
          ),
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.item});

  final AttendanceHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final present = item.status == 'PRESENT';
    final tone = present ? ProductColors.success : ProductColors.error;
    return Padding(
      padding: const EdgeInsets.only(bottom: ProductSpacing.x2),
      child: GlassCard(
        radius: ProductRadius.large,
        padding: const EdgeInsets.symmetric(
            horizontal: ProductSpacing.x3, vertical: ProductSpacing.x3),
        child: LayoutBuilder(builder: (context, c) {
          // Pill moves under the text when the row is narrow or text is large.
          final stacked = c.maxWidth < 330 || _textScale(context) > 1.4;
          final pill = NeonPill(
              label: present ? 'Present' : 'Absent',
              color: tone,
              icon: present ? Icons.check_rounded : Icons.close_rounded);
          return Row(
            crossAxisAlignment:
                stacked ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(ProductRadius.medium),
                ),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(
                      present ? Icons.check_rounded : Icons.close_rounded,
                      color: tone,
                      size: 22),
                ),
              ),
              const SizedBox(width: ProductSpacing.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_date(item.scheduledStart),
                        style: text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontFeatures: tabularFigures),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    Text(_subtitle(item),
                        style: text.bodyMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    if (stacked) ...[
                      const SizedBox(height: ProductSpacing.x1),
                      pill,
                    ],
                  ],
                ),
              ),
              if (!stacked) ...[
                const SizedBox(width: ProductSpacing.x2),
                pill,
              ],
            ],
          );
        }),
      ),
    );
  }

  static String _subtitle(AttendanceHistoryItem item) {
    final method = _method(item.method);
    final d = _institutionTime(item.scheduledStart);
    if (d == null) return method;
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$hh:$mm · $method';
  }

  static String _method(String? m) {
    switch (m) {
      case null:
        return 'Recorded by the system';
      case 'SECURE_PROOF':
        return 'Verified QR scan';
      case 'DYNAMIC_QR':
        return 'Verified QR scan';
      case 'FACULTY_ATTESTATION':
        return 'Marked by faculty';
      default:
        return m;
    }
  }

  static String _date(String value) {
    final p = _institutionTime(value);
    if (p == null) return value;
    return '${_weekdayShort[p.weekday - 1]}, ${p.day} ${_monthShort[p.month - 1]} ${p.year}';
  }
}
