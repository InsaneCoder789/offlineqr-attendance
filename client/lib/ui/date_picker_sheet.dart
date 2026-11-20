import 'package:flutter/material.dart';

import 'dark_kit_extra_a.dart';
import 'date_picker_common.dart';
import 'product_theme.dart';
import 'responsive.dart';

/// Opens the month-grid sheet and resolves with the chosen day (or null when
/// dismissed).
Future<DateTime?> showDayPickerSheet(
  BuildContext context, {
  required DateTime selected,
  required DateTime today,
  required ClassCountOf classCountOf,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: ProductColors.surface,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    constraints: const BoxConstraints(maxWidth: 480),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => MonthGridSheet(
      selected: selected,
      today: today,
      classCountOf: classCountOf,
    ),
  );
}

/// Full month grid: paging arrows, swipe between months, today marker,
/// class-day dots and a neon selected circle. Not Flutter's stock picker.
class MonthGridSheet extends StatefulWidget {
  const MonthGridSheet({
    super.key,
    required this.selected,
    required this.today,
    required this.classCountOf,
    this.monthsBefore = 24,
    this.monthsAfter = 36,
  });

  final DateTime selected;
  final DateTime today;
  final ClassCountOf classCountOf;
  final int monthsBefore;
  final int monthsAfter;

  @override
  State<MonthGridSheet> createState() => _MonthGridSheetState();
}

class _MonthGridSheetState extends State<MonthGridSheet> {
  late final int _base;
  late final int _count;
  late final PageController _pages;
  late int _page;

  @override
  void initState() {
    super.initState();
    final todayM = monthIndex(widget.today);
    final selM = monthIndex(widget.selected);
    final first = todayM - widget.monthsBefore;
    _base = first < selM - 1 ? first : selM - 1;
    final last = todayM + widget.monthsAfter > selM + 1 ? todayM + widget.monthsAfter : selM + 1;
    _count = last - _base + 1;
    _page = selM - _base;
    _pages = PageController(initialPage: _page);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  DateTime get _visible => monthFromIndex(_base + _page);

  void _go(int page) {
    final target = page.clamp(0, _count - 1);
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(target);
    } else {
      _pages.animateToPage(target,
          duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final compactHeight = media.size.height <= 420;
    final cellH = compactHeight ? 40.0 : 48.0;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final text = Theme.of(context).textTheme;
    final today = dayOnly(widget.today);

    return CappedTextScale(
      max: 1.3,
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              ProductSpacing.x3, ProductSpacing.x3, ProductSpacing.x3, ProductSpacing.x4 + media.viewPadding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: ProductSpacing.x2),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous month',
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    onPressed: _page > 0 ? () => _go(_page - 1) : null,
                    icon: Icon(rtl ? Icons.chevron_right_rounded : Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      header: true,
                      child: Text(
                        monthYearLabel(_visible),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next month',
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    onPressed: _page < _count - 1 ? () => _go(_page + 1) : null,
                    icon: Icon(rtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded),
                  ),
                ],
              ),
              const SizedBox(height: ProductSpacing.x1),
              ExcludeSemantics(
                child: Row(
                  children: [
                    for (final w in kWeekdayNames)
                      Expanded(
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              w.substring(0, 3).toUpperCase(),
                              maxLines: 1,
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                  color: ProductColors.textMuted),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: ProductSpacing.x2),
              SizedBox(
                height: cellH * 6,
                child: PageView.builder(
                  controller: _pages,
                  itemCount: _count,
                  onPageChanged: (p) => setState(() => _page = p),
                  itemBuilder: (context, i) => _MonthGrid(
                    month: monthFromIndex(_base + i),
                    cellHeight: cellH,
                    selected: dayOnly(widget.selected),
                    today: today,
                    classCountOf: widget.classCountOf,
                    onPick: (d) => Navigator.of(context).pop(d),
                  ),
                ),
              ),
              const SizedBox(height: ProductSpacing.x3),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(color: ProductColors.brandPrimary, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: ProductSpacing.x2),
                  Expanded(
                    child: Text('Days with classes',
                        style: text.bodySmall?.copyWith(color: ProductColors.textSecondary)),
                  ),
                ],
              ),
              const SizedBox(height: ProductSpacing.x3),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).pop(today),
                icon: const Icon(Icons.today_outlined, size: 20),
                label: const Text('Today'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.cellHeight,
    required this.selected,
    required this.today,
    required this.classCountOf,
    required this.onPick,
  });

  final DateTime month;
  final double cellHeight;
  final DateTime selected;
  final DateTime today;
  final ClassCountOf classCountOf;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final lead = DateTime(month.year, month.month, 1).weekday - 1;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final rows = ((lead + days) / 7).ceil();
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Column(
      children: [
        for (var r = 0; r < rows; r++)
          SizedBox(
            height: cellHeight,
            child: Row(
              children: [
                for (var c = 0; c < 7; c++)
                  Expanded(
                    child: Builder(builder: (context) {
                      final day = r * 7 + c - lead + 1;
                      if (day < 1 || day > days) return const SizedBox.shrink();
                      final date = DateTime(month.year, month.month, day);
                      return _DayCell(
                        date: date,
                        height: cellHeight,
                        selected: sameDay(date, selected),
                        isToday: sameDay(date, today),
                        classes: classCountOf(date),
                        reduced: reduced,
                        onTap: () => onPick(date),
                      );
                    }),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.height,
    required this.selected,
    required this.isToday,
    required this.classes,
    required this.reduced,
    required this.onTap,
  });

  final DateTime date;
  final double height;
  final bool selected;
  final bool isToday;
  final int classes;
  final bool reduced;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final d = (box.maxWidth < height - 4 ? box.maxWidth : height - 4).clamp(24.0, 44.0);
      final fg = selected ? ProductColors.onBrand : ProductColors.textPrimary;
      return Semantics(
        button: true,
        selected: selected,
        excludeSemantics: true,
        label: dayLabel(date, classes: classes, today: isToday),
        onTap: onTap,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Center(
            child: AnimatedContainer(
              duration: reduced ? Duration.zero : const Duration(milliseconds: 160),
              width: d,
              height: d,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? ProductColors.brandPrimary : Colors.transparent,
                border: isToday && !selected
                    ? Border.all(color: ProductColors.brandPrimary, width: 1.6)
                    : null,
                boxShadow: selected
                    ? [BoxShadow(color: ProductColors.brandPrimary.withValues(alpha: 0.45), blurRadius: 14, spreadRadius: -3)]
                    : null,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${date.day}',
                          maxLines: 1,
                          style: TextStyle(
                              fontSize: 16,
                              height: 1.15,
                              fontWeight: selected || isToday ? FontWeight.w800 : FontWeight.w600,
                              color: fg,
                              fontFeatures: tabularFigures)),
                      const SizedBox(height: 2),
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: classes > 0
                              ? (selected ? ProductColors.onBrand : ProductColors.brandPrimary)
                              : Colors.transparent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}
