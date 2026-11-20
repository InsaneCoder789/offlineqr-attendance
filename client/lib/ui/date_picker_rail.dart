import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import 'dark_kit_extra_a.dart';
import 'date_picker_common.dart';
import 'product_theme.dart';
import 'responsive.dart';

/// Horizontally scrolling rail of large day chips. The selected day is always
/// centred and the rail snaps chip by chip. Chips grow with the text scale so
/// nothing ever clips.
class DayRail extends StatefulWidget {
  const DayRail({
    super.key,
    required this.selected,
    required this.today,
    required this.onSelected,
    required this.classCountOf,
    this.daysBefore = 14,
    this.daysAfter = 28,
  });

  final DateTime selected;
  final DateTime today;
  final ValueChanged<DateTime> onSelected;
  final ClassCountOf classCountOf;
  final int daysBefore;
  final int daysAfter;

  @override
  State<DayRail> createState() => _DayRailState();
}

const double _kGap = 12;
const double _kChipMinW = 60;
const double _kChipMinH = 84;

class _DayRailState extends State<DayRail> {
  late DateTime _first;
  late DateTime _last;
  ScrollController? _controller;
  double _extent = _kChipMinW + _kGap;

  @override
  void initState() {
    super.initState();
    _computeRange();
  }

  void _computeRange() {
    final today = dayOnly(widget.today);
    final sel = dayOnly(widget.selected);
    final a = addDays(today, -widget.daysBefore);
    final b = addDays(today, widget.daysAfter);
    final selA = addDays(sel, -widget.daysBefore ~/ 2);
    final selB = addDays(sel, widget.daysAfter ~/ 2);
    _first = a.isBefore(selA) ? a : selA;
    _last = b.isAfter(selB) ? b : selB;
  }

  int get _count => daysBetween(_first, _last) + 1;

  int _indexOf(DateTime d) =>
      daysBetween(_first, dayOnly(d)).clamp(0, _count - 1);

  double _scale(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(14) / 14;

  ({double w, double h}) _chipSize(double s) {
    final c = s.clamp(1.0, 1.6);
    return (w: _kChipMinW * (1 + (c - 1) * 0.45), h: _kChipMinH * (1 + (c - 1) * 0.6));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = _chipSize(_scale(context));
    final extent = size.w + _kGap;
    if (_controller == null) {
      _extent = extent;
      _controller = ScrollController(initialScrollOffset: _indexOf(widget.selected) * extent);
    } else if (extent != _extent) {
      _extent = extent;
      _jumpAfterFrame();
    }
  }

  @override
  void didUpdateWidget(DayRail old) {
    super.didUpdateWidget(old);
    final sel = dayOnly(widget.selected);
    final outside = sel.isBefore(_first) || sel.isAfter(_last);
    if (outside || !sameDay(old.today, widget.today)) {
      final before = _first;
      _computeRange();
      if (!sameDay(before, _first) || outside) _jumpAfterFrame();
    } else if (!sameDay(old.selected, widget.selected)) {
      _centre(widget.selected);
    }
  }

  void _jumpAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _controller;
      if (!mounted || c == null || !c.hasClients) return;
      c.jumpTo(_clamp(c, _indexOf(widget.selected) * _extent));
    });
  }

  double _clamp(ScrollController c, double v) =>
      v.clamp(c.position.minScrollExtent, c.position.maxScrollExtent);

  void _centre(DateTime d) {
    final c = _controller;
    if (c == null || !c.hasClients) return;
    final target = _clamp(c, _indexOf(d) * _extent);
    if (MediaQuery.disableAnimationsOf(context)) {
      c.jumpTo(target);
    } else {
      c.animateTo(target, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CappedTextScale(
      max: 1.6,
      child: Builder(builder: (context) {
        final size = _chipSize(_scale(context));
        final reduced = MediaQuery.disableAnimationsOf(context);
        final today = dayOnly(widget.today);
        final sel = dayOnly(widget.selected);
        return Semantics(
          container: true,
          label: 'Day selector',
          child: SizedBox(
            height: size.h + 12,
            child: LayoutBuilder(builder: (context, box) {
              final pad = ((box.maxWidth - _extent) / 2).clamp(0.0, double.infinity);
              return ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) => const LinearGradient(
                  colors: [Color(0x00FFFFFF), Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
                  stops: [0, 0.05, 0.95, 1],
                ).createShader(rect),
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    scrollbars: false,
                    dragDevices: {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.mouse,
                      PointerDeviceKind.stylus,
                      PointerDeviceKind.trackpad,
                    },
                  ),
                  child: ListView.builder(
                    controller: _controller,
                    scrollDirection: Axis.horizontal,
                    physics: _SnapPhysics(extent: _extent),
                    itemExtent: _extent,
                    padding: EdgeInsets.symmetric(horizontal: pad, vertical: 6),
                    itemCount: _count,
                    itemBuilder: (context, i) {
                      final date = addDays(_first, i);
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: _kGap / 2),
                        child: _DayChip(
                          date: date,
                          selected: sameDay(date, sel),
                          isToday: sameDay(date, today),
                          classes: widget.classCountOf(date),
                          reduced: reduced,
                          onTap: () => widget.onSelected(date),
                          onFocus: () => _centre(date),
                        ),
                      );
                    },
                  ),
                ),
              );
            }),
          ),
        );
      }),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.date,
    required this.selected,
    required this.isToday,
    required this.classes,
    required this.reduced,
    required this.onTap,
    required this.onFocus,
  });

  final DateTime date;
  final bool selected;
  final bool isToday;
  final int classes;
  final bool reduced;
  final VoidCallback onTap;
  final VoidCallback onFocus;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? ProductColors.onBrand : ProductColors.textPrimary;
    final sub = selected ? ProductColors.onBrand : ProductColors.textSecondary;
    final ring = selected
        ? ProductColors.brandPrimary
        : (isToday ? ProductColors.brandPrimary : Colors.white.withValues(alpha: 0.07));
    return Semantics(
      button: true,
      selected: selected,
      excludeSemantics: true,
      label: dayLabel(date, classes: classes, today: isToday),
      onTap: onTap,
      child: Material(
        color: selected ? ProductColors.brandPrimary : ProductColors.surface,
        animationDuration: reduced ? Duration.zero : const Duration(milliseconds: 200),
        elevation: selected ? 6 : 0,
        shadowColor: ProductColors.brandPrimary,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: ring, width: isToday && !selected ? 1.6 : 1),
        ),
        child: InkWell(
          onTap: onTap,
          onFocusChange: (focused) {
            if (focused) onFocus();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: ProductSpacing.x2, horizontal: 4),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      kWeekdayNames[date.weekday - 1].substring(0, 3).toUpperCase(),
                      maxLines: 1,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: sub),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${date.day}',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 26,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: fg,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 6,
                      height: 6,
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
  }
}

/// Snaps the rail to whole chips; flings carry to the neighbouring chip.
class _SnapPhysics extends ScrollPhysics {
  const _SnapPhysics({required this.extent, super.parent});

  final double extent;

  @override
  _SnapPhysics applyTo(ScrollPhysics? ancestor) =>
      _SnapPhysics(extent: extent, parent: buildParent(ancestor));

  double _target(ScrollMetrics m, double velocity) {
    var item = m.pixels / extent;
    if (velocity < -toleranceFor(m).velocity) {
      item -= 0.5;
    } else if (velocity > toleranceFor(m).velocity) {
      item += 0.5;
    }
    return (item.roundToDouble() * extent).clamp(m.minScrollExtent, m.maxScrollExtent);
  }

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    if ((velocity <= 0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final target = _target(position, velocity);
    if (target == position.pixels) return null;
    return ScrollSpringSimulation(spring, position.pixels, target, velocity,
        tolerance: toleranceFor(position));
  }

  @override
  bool get allowImplicitScrolling => false;
}
