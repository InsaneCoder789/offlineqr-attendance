import 'package:flutter/material.dart';

import 'product_theme.dart';

/// Window size classes shared by every screen.
enum WindowClass { compact, medium, expanded }

class Breakpoints {
  const Breakpoints._();

  static const medium = 600.0;
  static const expanded = 840.0;

  static WindowClass of(double width) {
    if (width >= expanded) return WindowClass.expanded;
    if (width >= medium) return WindowClass.medium;
    return WindowClass.compact;
  }
}

/// Institution wall-clock time (IST, UTC+5:30), independent of the phone's
/// time zone, so "starts in" and "today" match what the faculty sees.
DateTime institutionNow() =>
    DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));

/// Height of the floating bottom navigation bar that overlaps the tab pages.
/// [AdaptivePage] reads it, so every tab gets matching bottom padding and no
/// content ends up hidden behind the bar. Zero outside the student shell.
class ShellInsets extends InheritedWidget {
  const ShellInsets({super.key, required this.bottom, required super.child});

  final double bottom;

  static double bottomOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellInsets>()?.bottom ?? 0;

  @override
  bool updateShouldNotify(ShellInsets old) => old.bottom != bottom;
}

/// Scrollable, centred, max-width page body with adaptive side padding.
/// Content can never overflow vertically: it scrolls instead.
class AdaptivePage extends StatelessWidget {
  const AdaptivePage({
    super.key,
    required this.children,
    this.maxWidth = 640,
    this.bottomPadding = ProductSpacing.x8,
    this.onRefresh,
  });

  final List<Widget> children;
  final double maxWidth;
  final double bottomPadding;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final inset = ShellInsets.bottomOf(context);
    final bottom = inset > 0
        ? inset + (bottomPadding < ProductSpacing.x4 ? bottomPadding : ProductSpacing.x4)
        : bottomPadding;
    final scroll = LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.maxWidth >= Breakpoints.medium
            ? ProductSpacing.x6
            : ProductSpacing.x4;
        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, 0, side, bottom),
              sliver: SliverToBoxAdapter(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    return onRefresh == null
        ? scroll
        : RefreshIndicator(onRefresh: onRefresh!, child: scroll);
  }
}

/// Caps system text scaling for dense chrome (chips, tab labels) so it stays
/// legible without breaking the layout; body copy keeps the full scale.
class CappedTextScale extends StatelessWidget {
  const CappedTextScale({super.key, required this.child, this.max = 1.3});

  final Widget child;
  final double max;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        textScaler: media.textScaler.clamp(maxScaleFactor: max),
      ),
      child: child,
    );
  }
}
