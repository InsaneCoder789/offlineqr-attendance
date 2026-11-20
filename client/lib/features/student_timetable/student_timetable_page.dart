import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/database/local_database.dart';
import '../../ui/dark_kit.dart';
import '../../ui/dark_kit_extra_a.dart';
import '../../ui/date_picker_common.dart';
import '../../ui/date_picker_strip.dart';
import '../../ui/product_theme.dart';
import '../../ui/responsive.dart';
import '../../ui/state_views.dart';

/// Timetable: date picker, one hero for the live/next class, and an agenda.
/// Everything lives in a scroll view, so no text size or screen height can
/// overflow it. "Today" and countdowns use institution time (IST).
///
/// Database reads are synchronous, so there is no loading skeleton: the first
/// frame already has data. A thrown read shows [StateView.error] with retry.
class StudentTimetablePage extends StatefulWidget {
  const StudentTimetablePage({
    super.key,
    required this.database,
    this.syncError,
    this.onSync,
  });

  final LocalAttendanceDatabase database;

  /// Last sync failure, if any. Shows an offline strip above the content.
  final String? syncError;

  /// Offered as the action when no timetable has been synced yet.
  final Future<void> Function()? onSync;

  @override
  State<StudentTimetablePage> createState() => _StudentTimetablePageState();
}

class _StudentTimetablePageState extends State<StudentTimetablePage> {
  late DateTime _selected = dayOnly(institutionNow());
  DateTime _now = institutionNow();
  List<List<TimetableItem>> _week = const [];
  Object? _error;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = institutionNow());
    });
  }

  @override
  void didUpdateWidget(StudentTimetablePage old) {
    super.didUpdateWidget(old);
    if (old.database != widget.database) _load();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _load() {
    try {
      _week = [for (var d = 1; d <= 7; d++) widget.database.getTimetableForDay(d)];
      _error = null;
    } catch (e) {
      _week = const [];
      _error = e;
    }
  }

  int _countOf(DateTime d) => _week.isEmpty ? 0 : _week[d.weekday - 1].length;

  /// First day after [from] (within eight weeks) that has classes.
  DateTime? _nextClassDay(DateTime from) {
    for (var i = 1; i <= 56; i++) {
      final d = addDays(from, i);
      if (_countOf(d) > 0) return d;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final now = _now;
    final today = dayOnly(now);
    final sel = _selected;
    final isToday = sameDay(sel, today);
    final isPast = sel.isBefore(today);
    final failed = _error != null;
    final hasAny = _week.any((d) => d.isNotEmpty);
    final items = failed ? const <TimetableItem>[] : _week[sel.weekday - 1];
    final phases = [for (final i in items) _phaseOf(i, now, isToday, isPast)];
    final liveIndex = phases.indexOf(_Phase.now);
    final nextIndex = phases.indexOf(_Phase.upcoming);
    final heroIndex = isToday ? (liveIndex >= 0 ? liveIndex : nextIndex) : -1;
    final allDone = isToday && items.isNotEmpty && phases.every((p) => p == _Phase.done);
    final jumpTo = items.isEmpty || allDone ? _nextClassDay(sel) : null;

    return Scaffold(
      body: SafeArea(
        child: AdaptivePage(
          children: [
            _Header(date: sel),
            const SizedBox(height: ProductSpacing.x3),
            if (widget.syncError != null && !failed) ...[
              const StatusStrip(message: 'Can\'t sync right now. Showing your saved timetable.'),
              const SizedBox(height: ProductSpacing.x3),
            ],
            if (failed)
              StateView.error(
                title: 'Couldn\'t load your timetable',
                message: 'Please try again. Your saved data is safe on this phone.',
                onAction: () => setState(_load),
              )
            else ...[
              DatePickerStrip(
                selected: sel,
                today: today,
                classCountOf: _countOf,
                onSelected: (d) => setState(() => _selected = dayOnly(d)),
              ),
              const SizedBox(height: ProductSpacing.x5),
              if (!hasAny)
                StateView.empty(
                  icon: Icons.cloud_download_outlined,
                  title: 'No timetable yet',
                  message: 'Sync to download your timetable. Once synced it works offline.',
                  actionLabel: widget.onSync != null ? 'Sync now' : null,
                  onAction: widget.onSync == null ? null : () => widget.onSync!(),
                )
              else if (items.isEmpty)
                StateView.empty(
                  icon: Icons.event_available_outlined,
                  title: 'No classes this day',
                  message: jumpTo == null
                      ? 'Nothing is scheduled. Your synced timetable stays available offline.'
                      : 'Nothing is scheduled. Enjoy the free time.',
                  actionLabel: jumpTo == null ? null : 'Jump to ${_shortDate(jumpTo)}',
                  onAction: jumpTo == null ? null : () => setState(() => _selected = jumpTo),
                )
              else ...[
                if (heroIndex >= 0) ...[
                  _Hero(item: items[heroIndex], live: phases[heroIndex] == _Phase.now, now: now),
                  const SizedBox(height: ProductSpacing.x5),
                ] else if (allDone) ...[
                  StateView.empty(
                    icon: Icons.check_circle_outline_rounded,
                    title: 'Classes are over',
                    message: 'Today\'s classes are complete. Attendance stays available offline.',
                    compact: true,
                    actionLabel: jumpTo == null ? null : 'Jump to ${_shortDate(jumpTo)}',
                    onAction: jumpTo == null ? null : () => setState(() => _selected = jumpTo),
                  ),
                  const SizedBox(height: ProductSpacing.x5),
                ],
                _AgendaHeading(count: items.length),
                const SizedBox(height: ProductSpacing.x2),
                for (var i = 0; i < items.length; i++)
                  RepaintBoundary(
                    child: Reveal(
                      index: i,
                      child: _AgendaRow(
                        item: items[i],
                        phase: phases[i],
                        isNext: isToday && i == nextIndex && liveIndex < 0,
                        clash: _clashes(items, i),
                      ),
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  static String _shortDate(DateTime d) => '${kWeekdayNames[d.weekday - 1]} ${d.day}';

  static bool _clashes(List<TimetableItem> items, int i) {
    final a = items[i];
    final aStart = _minutes(a.startTime);
    final aEnd = _minutes(a.endTime);
    for (var j = 0; j < items.length; j++) {
      if (j == i) continue;
      if (aStart < _minutes(items[j].endTime) && _minutes(items[j].startTime) < aEnd) return true;
    }
    return false;
  }

  static _Phase _phaseOf(TimetableItem item, DateTime now, bool isToday, bool isPast) {
    if (isPast) return _Phase.done;
    if (!isToday) return _Phase.upcoming;
    final current = now.hour * 60 + now.minute;
    final start = _minutes(item.startTime);
    final end = _minutes(item.endTime);
    if (current >= start && current <= end) return _Phase.now;
    return current < start ? _Phase.upcoming : _Phase.done;
  }
}

enum _Phase { done, now, upcoming }

int _minutes(String value) {
  final p = value.split(':');
  return int.parse(p[0]) * 60 + int.parse(p[1]);
}

String _hhmm(String v) => v.length >= 5 ? v.substring(0, 5) : v;

class _Header extends StatelessWidget {
  const _Header({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: ProductSpacing.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Timetable',
              style: text.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.2, height: 1.05),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(
            '${kWeekdayNames[date.weekday - 1]}, ${date.day} ${kMonthNames[date.month - 1]}',
            style: text.bodyLarge?.copyWith(color: ProductColors.textSecondary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _AgendaHeading extends StatelessWidget {
  const _AgendaHeading({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
          letterSpacing: 1.6,
          fontWeight: FontWeight.w800,
          color: ProductColors.textMuted,
        );
    return Row(
      children: [
        Text('AGENDA', style: style),
        const SizedBox(width: ProductSpacing.x2),
        Expanded(
          child: Text(classCountLabel(count),
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style?.copyWith(letterSpacing: 0.4)),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.item, required this.live, required this.now});

  final TimetableItem item;
  final bool live;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final current = now.hour * 60 + now.minute;
    final mins = live ? _minutes(item.endTime) - current : _minutes(item.startTime) - current;
    final text = Theme.of(context).textTheme;
    final m = mins < 0 ? 0 : mins;
    final big = live ? '${m.clamp(0, 999)}' : (m < 60 ? '$m' : '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}');
    final unit = live ? 'min left' : (m < 60 ? 'min to start' : 'h to start');
    return NeonHero(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: ProductSpacing.x3,
            runSpacing: ProductSpacing.x2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              NeonPill(
                label: live ? 'Happening now' : 'Up next',
                icon: live ? Icons.bolt_rounded : Icons.schedule_rounded,
                filled: true,
              ),
              Text(
                live ? '$m min left' : 'Starts in ${_countdown(mins)}',
                style: text.labelLarge?.copyWith(color: ProductColors.textSecondary, fontFeatures: tabularFigures),
              ),
            ],
          ),
          const SizedBox(height: ProductSpacing.x5),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(big,
                      style: text.displayLarge?.copyWith(
                          fontSize: 76,
                          height: 1.0,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -3,
                          color: ProductColors.textPrimary,
                          fontFeatures: tabularFigures)),
                ),
              ),
              const SizedBox(width: ProductSpacing.x2),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(unit,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(color: ProductColors.brandPrimary, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
          const SizedBox(height: ProductSpacing.x3),
          Text(item.courseName,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: text.headlineSmall?.copyWith(
                  color: ProductColors.textPrimary, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          const SizedBox(height: ProductSpacing.x3),
          Wrap(
            spacing: ProductSpacing.x4,
            runSpacing: ProductSpacing.x2,
            children: [
              _Meta(icon: Icons.schedule_rounded, label: '${_hhmm(item.startTime)} – ${_hhmm(item.endTime)}', color: ProductColors.textPrimary),
              _Meta(icon: Icons.meeting_room_outlined, label: item.room, color: ProductColors.textPrimary),
              _Meta(icon: Icons.groups_outlined, label: item.sectionCode, color: ProductColors.textPrimary),
            ],
          ),
        ],
      ),
    );
  }

  static String _countdown(int mins) {
    final m = mins < 0 ? 0 : mins;
    if (m < 60) return '$m min';
    return '${m ~/ 60} h ${m % 60} min';
  }
}

class _AgendaRow extends StatelessWidget {
  const _AgendaRow({required this.item, required this.phase, required this.isNext, required this.clash});

  final TimetableItem item;
  final _Phase phase;
  final bool isNext;
  final bool clash;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final live = phase == _Phase.now;
    final done = phase == _Phase.done;
    final accent = courseAccent(item.courseCode);
    return Padding(
      padding: const EdgeInsets.only(bottom: ProductSpacing.x3),
      child: Opacity(
        opacity: done ? 0.62 : 1,
        child: GlassCard(
          padding: EdgeInsets.zero,
          radius: ProductRadius.large + 2,
          glow: live ? accent : null,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 5,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: const BorderRadiusDirectional.horizontal(start: Radius.circular(ProductRadius.large + 2)),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(ProductSpacing.x4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: ProductSpacing.x2,
                          runSpacing: ProductSpacing.x1,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(_hhmm(item.startTime),
                                style: text.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.8,
                                    color: done ? ProductColors.textMuted : accent,
                                    fontFeatures: tabularFigures)),
                            if (live) const NeonPill(label: 'Now', icon: Icons.bolt_rounded, filled: true)
                            else if (isNext) NeonPill(label: 'Next', icon: Icons.schedule_rounded, color: accent)
                            else if (done) const NeonPill(label: 'Done', icon: Icons.check_rounded, color: ProductColors.textMuted),
                            if (clash) const NeonPill(label: 'Overlaps', icon: Icons.layers_outlined, color: ProductColors.warning),
                          ],
                        ),
                        const SizedBox(height: ProductSpacing.x2),
                        Text(item.courseName,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: done ? ProductColors.textSecondary : ProductColors.textPrimary)),
                        const SizedBox(height: ProductSpacing.x2),
                        Wrap(
                          spacing: ProductSpacing.x3,
                          runSpacing: ProductSpacing.x1,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _Meta(icon: Icons.schedule_rounded, label: '${_hhmm(item.startTime)} – ${_hhmm(item.endTime)}', color: ProductColors.textSecondary),
                            _Meta(icon: Icons.meeting_room_outlined, label: item.room, color: ProductColors.textSecondary),
                            _Meta(icon: Icons.school_outlined, label: item.courseCode, color: accent),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: color, fontWeight: FontWeight.w700, fontFeatures: tabularFigures)),
        ),
      ],
    );
  }
}
