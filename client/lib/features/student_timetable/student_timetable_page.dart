import 'package:flutter/material.dart';

import '../../core/database/local_database.dart';
import '../../ui/kiit_components.dart';
import '../../ui/kiit_theme.dart';

class StudentTimetablePage extends StatefulWidget {
  const StudentTimetablePage({super.key, required this.database});

  final LocalAttendanceDatabase database;

  @override
  State<StudentTimetablePage> createState() => _StudentTimetablePageState();
}

class _StudentTimetablePageState extends State<StudentTimetablePage> {
  late DateTime selectedDate;

  @override
  void initState() {
    super.initState();
    selectedDate = DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final items = widget.database.getTimetableForDay(selectedDate.weekday);
    final isShowingToday = _isSameDay(selectedDate, today);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Section
            Padding(
              padding: const EdgeInsets.fromLTRB(KiitSpacing.x4, KiitSpacing.x4,
                  KiitSpacing.x4, KiitSpacing.x2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Timetable',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: KiitColors.textPrimary,
                              ),
                        ),
                        const SizedBox(height: KiitSpacing.x1),
                        Text(
                          _fullDateLabel(selectedDate),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: KiitColors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: KiitSpacing.x3),
                  if (!isShowingToday)
                    OutlinedButton.icon(
                      onPressed: () => setState(() => selectedDate = today),
                      icon: const Icon(Icons.today_outlined, size: 18),
                      label: const Text('Today'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: KiitSpacing.x3,
                          vertical: KiitSpacing.x1,
                        ),
                        minimumSize: const Size(80, 36),
                      ),
                    ),
                ],
              ),
            ),

            // Date Strip Selector
            Padding(
              padding: const EdgeInsets.symmetric(vertical: KiitSpacing.x2),
              child: _DateStrip(
                selectedDate: selectedDate,
                onSelected: (date) => setState(() => selectedDate = date),
              ),
            ),

            const Divider(),

            // Timeline Header
            Padding(
              padding: const EdgeInsets.fromLTRB(KiitSpacing.x4, KiitSpacing.x4,
                  KiitSpacing.x4, KiitSpacing.x2),
              child: Text(
                _weekdayName(selectedDate.weekday).toUpperCase(),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      color: KiitColors.textMuted,
                    ),
              ),
            ),

            Expanded(
              child: items.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(KiitSpacing.x4),
                      child: Center(
                        child: CuteEmptyState(
                          title: 'Classes are over',
                          message:
                              'No classes are scheduled for this day. Your synced timetable is still available offline.',
                        ),
                      ),
                    )
                  : _buildClassList(items, today),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClassList(List<TimetableItem> items, DateTime now) {
    final states = [for (final item in items) _getClassState(item, now)];
    final nowIndex = states.indexOf(_ClassState.now);
    final nextIndex = states.indexOf(_ClassState.upcoming);
    final currentIndex = nowIndex >= 0 ? nowIndex : nextIndex;
    final allCompleted = _isSameDay(selectedDate, now) &&
        states.every((s) => s == _ClassState.completed);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: KiitSpacing.x4,
        vertical: KiitSpacing.x2,
      ),
      itemCount: items.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          if (currentIndex >= 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: KiitSpacing.x4),
              child: RepaintBoundary(
                child: _CurrentClassCard(
                  item: items[currentIndex],
                  state: states[currentIndex],
                  now: now,
                ),
              ),
            );
          }
          if (allCompleted) {
            return const Padding(
              padding: EdgeInsets.only(bottom: KiitSpacing.x4),
              child: CuteEmptyState(
                title: 'Classes are over',
                message:
                    'Your scheduled classes for today are complete. Attendance records stay available offline.',
              ),
            );
          }
          return const SizedBox.shrink();
        }
        final itemIndex = index - 1;
        return RepaintBoundary(
          child: _ScheduleClassCard(
            item: items[itemIndex],
            state: states[itemIndex],
            isNext: itemIndex == nextIndex,
          ),
        );
      },
    );
  }

  _ClassState _getClassState(TimetableItem item, DateTime now) {
    if (!_isSameDay(selectedDate, now)) {
      return _ClassState.upcoming;
    }
    final start = _minutes(item.startTime);
    final end = _minutes(item.endTime);
    final current = now.hour * 60 + now.minute;

    if (current >= start && current <= end) {
      return _ClassState.now;
    } else if (current < start) {
      return _ClassState.upcoming;
    } else {
      return _ClassState.completed;
    }
  }

  int _minutes(String value) {
    final parts = value.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  String _weekdayName(int weekday) {
    const names = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    return names[weekday - 1];
  }

  String _fullDateLabel(DateTime date) {
    const months = [
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
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

enum _ClassState { completed, now, upcoming }

class _DateStrip extends StatelessWidget {
  const _DateStrip({required this.selectedDate, required this.onSelected});

  final DateTime selectedDate;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final monday = today.subtract(Duration(days: today.weekday - 1));

    return SizedBox(
      height: 84,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: KiitSpacing.x4),
        itemCount: 7,
        itemBuilder: (context, index) {
          final date = monday.add(Duration(days: index));
          final isSelected = date.weekday == selectedDate.weekday;
          final isToday = date.year == today.year &&
              date.month == today.month &&
              date.day == today.day;

          return Padding(
            padding: const EdgeInsets.only(right: KiitSpacing.x2),
            child: AspectRatio(
              aspectRatio: 0.85,
              child: Material(
                color: isSelected
                    ? KiitColors.brandPrimary
                    : isToday
                        ? KiitColors.brandPrimarySoft
                        : KiitColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(KiitRadius.medium),
                  side: BorderSide(
                    color: isSelected
                        ? KiitColors.brandPrimary
                        : isToday
                            ? KiitColors.brandPrimary.withValues(alpha: 0.3)
                            : KiitColors.border,
                    width: isToday || isSelected ? 1.5 : 1.0,
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(KiitRadius.medium),
                  onTap: () => onSelected(date),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: KiitSpacing.x2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _shortWeekday(date.weekday).toUpperCase(),
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : isToday
                                    ? KiitColors.brandPrimaryStrong
                                    : KiitColors.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: KiitSpacing.x1),
                        Text(
                          date.day.toString(),
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : KiitColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _shortWeekday(int weekday) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[weekday - 1];
  }
}

class _ScheduleClassCard extends StatelessWidget {
  const _ScheduleClassCard({
    required this.item,
    required this.state,
    required this.isNext,
  });

  final TimetableItem item;
  final _ClassState state;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final active = state == _ClassState.now;
    final completed = state == _ClassState.completed;
    final background = active
        ? KiitColors.brandPrimary
        : completed
            ? KiitColors.surface.withValues(alpha: 0.78)
            : KiitColors.surface;
    final primaryText = active ? Colors.white : KiitColors.textPrimary;
    final secondaryText = active
        ? Colors.white.withValues(alpha: 0.86)
        : KiitColors.textSecondary;
    final strongText = active ? Colors.white : KiitColors.brandPrimaryStrong;
    final chipTone = active
        ? _InCardChipTone.greenSolid
        : isNext
            ? _InCardChipTone.greenSoft
            : _InCardChipTone.neutral;

    return Padding(
      padding: const EdgeInsets.only(bottom: KiitSpacing.x3),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(KiitRadius.large),
          border: Border.all(
            color: active ? KiitColors.brandPrimary : KiitColors.border,
            width: active ? 0 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(KiitSpacing.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: KiitSpacing.x2,
                runSpacing: KiitSpacing.x2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _TimeBadge(
                    startTime: _formatTime(item.startTime),
                    endTime: _formatTime(item.endTime),
                    active: active,
                  ),
                  if (active)
                    const _InCardChip(
                      label: 'Now',
                      icon: Icons.bolt_rounded,
                      tone: _InCardChipTone.greenSolid,
                    )
                  else if (isNext)
                    const _InCardChip(
                      label: 'Next',
                      icon: Icons.schedule_rounded,
                      tone: _InCardChipTone.greenSoft,
                    )
                  else
                    _InCardChip(
                      label: state == _ClassState.completed
                          ? 'Completed'
                          : 'Upcoming',
                      icon: state == _ClassState.completed
                          ? Icons.check_circle_outline_rounded
                          : Icons.event_available_outlined,
                      tone: chipTone,
                    ),
                ],
              ),
              const SizedBox(height: KiitSpacing.x4),
              Text(
                item.courseName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: primaryText,
                    ),
              ),
              const SizedBox(height: KiitSpacing.x3),
              Wrap(
                spacing: KiitSpacing.x3,
                runSpacing: KiitSpacing.x2,
                children: [
                  _ClassMeta(
                    icon: Icons.school_outlined,
                    label: item.courseCode,
                    color: secondaryText,
                  ),
                  _ClassMeta(
                    icon: Icons.groups_outlined,
                    label: 'Sec ${item.sectionCode}',
                    color: secondaryText,
                  ),
                  _ClassMeta(
                    icon: Icons.meeting_room_outlined,
                    label: 'Room ${item.room}',
                    color: strongText,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(String value) {
    if (value.length >= 5) {
      return value.substring(0, 5);
    }
    return value;
  }
}

class _TimeBadge extends StatelessWidget {
  const _TimeBadge({
    required this.startTime,
    required this.endTime,
    required this.active,
  });

  final String startTime;
  final String endTime;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KiitSpacing.x3,
        vertical: KiitSpacing.x2,
      ),
      decoration: BoxDecoration(
        color: active
            ? Colors.white.withValues(alpha: 0.16)
            : KiitColors.brandPrimarySoft,
        borderRadius: BorderRadius.circular(KiitRadius.small),
        border: Border.all(
          color: active
              ? Colors.white.withValues(alpha: 0.24)
              : KiitColors.brandPrimary.withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.access_time_rounded,
            size: 15,
            color: active ? Colors.white : KiitColors.brandPrimaryStrong,
          ),
          const SizedBox(width: KiitSpacing.x1),
          Text(
            '$startTime - $endTime',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: active ? Colors.white : KiitColors.brandPrimaryStrong,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      ),
    );
  }
}

enum _InCardChipTone { greenSolid, greenSoft, neutral }

class _InCardChip extends StatelessWidget {
  const _InCardChip({
    required this.label,
    required this.icon,
    required this.tone,
  });

  final String label;
  final IconData icon;
  final _InCardChipTone tone;

  @override
  Widget build(BuildContext context) {
    final foreground = switch (tone) {
      _InCardChipTone.greenSolid => Colors.white,
      _InCardChipTone.greenSoft => KiitColors.brandPrimaryStrong,
      _InCardChipTone.neutral => KiitColors.textSecondary,
    };
    final background = switch (tone) {
      _InCardChipTone.greenSolid => Colors.white.withValues(alpha: 0.18),
      _InCardChipTone.greenSoft => KiitColors.brandPrimarySoft,
      _InCardChipTone.neutral => KiitColors.background,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KiitSpacing.x3,
        vertical: KiitSpacing.x2,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(KiitRadius.small),
        border: Border.all(color: foreground.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: KiitSpacing.x1),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      ),
    );
  }
}

class _CurrentClassCard extends StatelessWidget {
  const _CurrentClassCard({
    required this.item,
    required this.state,
    required this.now,
  });

  final TimetableItem item;
  final _ClassState state;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final isNow = state == _ClassState.now;
    final minutes = isNow
        ? _minutesLeft(item.endTime, now)
        : _minutesUntil(item.startTime, now);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: KiitColors.brandPrimary,
        borderRadius: BorderRadius.circular(KiitRadius.large),
      ),
      child: Padding(
        padding: const EdgeInsets.all(KiitSpacing.x5),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 330;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: KiitSpacing.x2,
                  runSpacing: KiitSpacing.x2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusChip(
                      label: isNow ? 'Happening now' : 'Next class',
                      tone: StatusTone.success,
                      icon: isNow ? Icons.bolt_rounded : Icons.schedule_rounded,
                    ),
                    Text(
                      isNow
                          ? '${minutes.clamp(0, 999)} min left'
                          : 'Starts in ${minutes.clamp(0, 999)} min',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: KiitSpacing.x4),
                Text(
                  item.courseName,
                  maxLines: compact ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: KiitSpacing.x3),
                Wrap(
                  spacing: KiitSpacing.x4,
                  runSpacing: KiitSpacing.x2,
                  children: [
                    _HeroMeta(
                      icon: Icons.schedule_rounded,
                      label: '${item.startTime} - ${item.endTime}',
                    ),
                    _HeroMeta(
                      icon: Icons.meeting_room_outlined,
                      label: item.room,
                    ),
                    _HeroMeta(
                      icon: Icons.groups_outlined,
                      label: item.sectionCode,
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  int _minutesUntil(String startTime, DateTime now) {
    final start = _minutes(startTime);
    final current = now.hour * 60 + now.minute;
    return start - current;
  }

  int _minutesLeft(String endTime, DateTime now) {
    final end = _minutes(endTime);
    final current = now.hour * 60 + now.minute;
    return end - current;
  }

  int _minutes(String value) {
    final parts = value.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }
}

class _ClassMeta extends StatelessWidget {
  const _ClassMeta({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: KiitSpacing.x1),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
        ),
      ],
    );
  }
}

class _HeroMeta extends StatelessWidget {
  const _HeroMeta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: Colors.white.withValues(alpha: 0.9)),
        const SizedBox(width: KiitSpacing.x1),
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
        ),
      ],
    );
  }
}
