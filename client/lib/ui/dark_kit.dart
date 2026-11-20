import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'product_theme.dart';

/// Shared primitives of the bold dark visual language.
/// Ink-black canvas, neon green accent, big numerals, glowing rings,
/// glass-like cards. Everything is overflow-safe (no fixed heights on text).

/// Card with a faint top-lit gradient, hairline border and optional glow.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(ProductSpacing.x5),
    this.radius = ProductRadius.hero,
    this.glow,
    this.onTap,
    this.tint,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? glow;
  final VoidCallback? onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final box = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            (tint ?? ProductColors.surfaceElevated),
            ProductColors.surface,
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        boxShadow: [
          if (glow != null)
            BoxShadow(color: glow!.withValues(alpha: 0.18), blurRadius: 36, spreadRadius: -6),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: box,
      ),
    );
  }
}

/// Neon accent hero: green radial glow on black, for the single most
/// important card on a screen.
class NeonHero extends StatelessWidget {
  const NeonHero({super.key, required this.child, this.padding = const EdgeInsets.all(ProductSpacing.x6)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const RadialGradient(
          center: Alignment(-0.7, -0.9),
          radius: 1.6,
          colors: [Color(0xFF1C6B3F), Color(0xFF0C2418), Color(0xFF08110D)],
          stops: [0.0, 0.55, 1.0],
        ),
        border: Border.all(color: ProductColors.brandPrimary.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(color: ProductColors.brandPrimary.withValues(alpha: 0.16), blurRadius: 40, spreadRadius: -8),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Glowing progress ring with a centred child (usually a big percentage).
class GlowRing extends StatelessWidget {
  const GlowRing({
    super.key,
    required this.value,
    required this.size,
    this.stroke = 10,
    this.color,
    this.child,
  });

  /// 0..100
  final double value;
  final double size;
  final double stroke;
  final Color? color;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = color ?? (value >= 75 ? ProductColors.brandPrimary : ProductColors.absent);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _RingPainter(value: (value / 100).clamp(0.0, 1.0), stroke: stroke, color: c),
          ),
          if (child != null)
            Padding(
              padding: EdgeInsets.all(stroke + 6),
              child: FittedBox(fit: BoxFit.scaleDown, child: child),
            ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.value, required this.stroke, required this.color});

  final double value;
  final double stroke;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = Colors.white.withValues(alpha: 0.07);
    canvas.drawArc(rect, 0, math.pi * 2, false, track);
    if (value <= 0) return;
    // A (near) full ring is painted as a solid circle: the sweep gradient's
    // start and end colours differ and would draw a hard seam at 12 o'clock.
    final full = value >= 0.999;
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke + 6
      ..strokeCap = full ? StrokeCap.butt : StrokeCap.round
      ..color = color.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = full ? StrokeCap.butt : StrokeCap.round;
    if (full) {
      arc.color = color;
      canvas.drawCircle(rect.center, rect.width / 2, glow);
      canvas.drawCircle(rect.center, rect.width / 2, arc);
      return;
    }
    final sweep = math.max(math.pi * 2 * value, 0.01);
    arc.shader = SweepGradient(
      startAngle: -math.pi / 2,
      endAngle: -math.pi / 2 + sweep,
      colors: [color.withValues(alpha: 0.65), color],
    ).createShader(rect);
    canvas.drawArc(rect, -math.pi / 2, sweep, false, glow);
    canvas.drawArc(rect, -math.pi / 2, sweep, false, arc);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.value != value || old.color != color || old.stroke != stroke;
}

/// Small rounded label. [filled] = neon fill with dark text.
class NeonPill extends StatelessWidget {
  const NeonPill({super.key, required this.label, this.icon, this.color, this.filled = false});

  final String label;
  final IconData? icon;
  final Color? color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = color ?? ProductColors.brandPrimary;
    final fg = filled ? ProductColors.onBrand : c;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: filled ? c : c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: filled ? null : Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: ProductSpacing.x3, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Oversized numeral with a small caption underneath.
class BigStat extends StatelessWidget {
  const BigStat({super.key, required this.value, required this.label, this.color});

  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: t.displaySmall?.copyWith(color: color ?? ProductColors.textPrimary, fontWeight: FontWeight.w800, height: 1.0)),
        ),
        const SizedBox(height: 4),
        Text(label, style: t.labelMedium?.copyWith(color: ProductColors.textMuted), maxLines: 2, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}
