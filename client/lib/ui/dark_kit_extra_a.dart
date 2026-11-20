import 'package:flutter/material.dart';

/// Extra primitives for the student screens (timetable / attendance / scan).

const List<Color> _neonPalette = [
  Color(0xFF2BD96B), // green
  Color(0xFF22D3EE), // cyan
  Color(0xFF9B7BFF), // violet
  Color(0xFFFFB84A), // amber
  Color(0xFFFF7A66), // coral
  Color(0xFFFF5FA8), // pink
];

/// Stable accent colour for a course, derived from its code.
Color courseAccent(String code) {
  var h = 0;
  for (final u in code.trim().toUpperCase().codeUnits) {
    h = (h * 31 + u) & 0x7fffffff;
  }
  return _neonPalette[h % _neonPalette.length];
}

const List<FontFeature> tabularFigures = [FontFeature.tabularFigures()];

/// Short fade + slide-in, staggered by [index]. Skipped when animations are
/// disabled.
class Reveal extends StatelessWidget {
  const Reveal({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;
    final delay = (index.clamp(0, 8)) * 40;
    final total = 250 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 14), child: child),
      ),
    );
  }
}
