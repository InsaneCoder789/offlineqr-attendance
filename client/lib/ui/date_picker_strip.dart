import 'package:flutter/material.dart';

import 'date_picker_common.dart';
import 'date_picker_rail.dart';
import 'date_picker_sheet.dart';
import 'product_theme.dart';
import 'responsive.dart';

/// Month/year label row (tappable) with a Today chip and a calendar button,
/// above a horizontally scrolling [DayRail]. The calendar button opens the
/// month-grid sheet and reports the chosen day through [onSelected].
class DatePickerStrip extends StatelessWidget {
  const DatePickerStrip({
    super.key,
    required this.selected,
    required this.today,
    required this.onSelected,
    required this.classCountOf,
  });

  final DateTime selected;
  final DateTime today;
  final ValueChanged<DateTime> onSelected;
  final ClassCountOf classCountOf;

  Future<void> _openCalendar(BuildContext context) async {
    final picked = await showDayPickerSheet(
      context,
      selected: selected,
      today: today,
      classCountOf: classCountOf,
    );
    if (picked != null) onSelected(dayOnly(picked));
  }

  @override
  Widget build(BuildContext context) {
    final isToday = sameDay(selected, today);
    final label = monthYearLabel(selected);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(builder: (context, box) {
          final iconOnly = box.maxWidth < 340;
          return CappedTextScale(
            max: 1.3,
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    button: true,
                    label: 'Choose date, $label',
                    excludeSemantics: true,
                    onTap: () => _openCalendar(context),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(ProductRadius.medium),
                      onTap: () => _openCalendar(context),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3),
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(Icons.expand_more_rounded, color: ProductColors.textSecondary),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: ProductSpacing.x2),
                _TodayChip(
                  iconOnly: iconOnly,
                  current: isToday,
                  onTap: () => onSelected(dayOnly(today)),
                ),
                const SizedBox(width: ProductSpacing.x1),
                IconButton.filledTonal(
                  tooltip: 'Open calendar',
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  style: IconButton.styleFrom(
                    backgroundColor: ProductColors.surfaceElevated,
                    foregroundColor: ProductColors.brandPrimary,
                  ),
                  onPressed: () => _openCalendar(context),
                  icon: const Icon(Icons.calendar_month_rounded),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: ProductSpacing.x1),
        DayRail(
          selected: selected,
          today: today,
          onSelected: onSelected,
          classCountOf: classCountOf,
        ),
      ],
    );
  }
}

class _TodayChip extends StatelessWidget {
  const _TodayChip({required this.iconOnly, required this.current, required this.onTap});

  final bool iconOnly;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = current ? ProductColors.textMuted : ProductColors.brandPrimary;
    return Semantics(
      button: true,
      enabled: !current,
      label: current ? 'Today, selected' : 'Jump to today',
      excludeSemantics: true,
      onTap: current ? null : onTap,
      child: Tooltip(
        message: 'Today',
        child: InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: current ? null : onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  color: current ? Colors.transparent : ProductColors.brandPrimary.withValues(alpha: 0.12),
                  border: Border.all(color: color.withValues(alpha: current ? 0.4 : 0.7)),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: iconOnly ? 8 : 12, vertical: 7),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.today_outlined, size: 18, color: color),
                      if (!iconOnly) ...[
                        const SizedBox(width: 6),
                        Text('Today',
                            maxLines: 1,
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(color: color, fontWeight: FontWeight.w800)),
                      ],
                    ],
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
