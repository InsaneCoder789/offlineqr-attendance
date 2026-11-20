import 'package:flutter/material.dart';

import 'dark_kit.dart';
import 'product_theme.dart';

/// Extra shared primitives for the bold dark language (set B).

/// Subtle fade + slide-in. Disabled when animations are disabled.
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.offset = 14,
  });

  final Widget child;
  final int index;
  final double offset;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return child;
    final delay = (index.clamp(0, 6)) * 30;
    final total = 200 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * offset), child: child),
      ),
    );
  }
}

/// Rounded icon chip: tinted square with a centred icon.
class IconChip extends StatelessWidget {
  const IconChip({
    super.key,
    required this.icon,
    this.size = 44,
    this.color,
    this.filled = false,
  });

  final IconData icon;
  final double size;
  final Color? color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = color ?? ProductColors.brandPrimary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: filled ? c : c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.32),
        border: filled ? null : Border.all(color: c.withValues(alpha: 0.28)),
        boxShadow: filled
            ? [BoxShadow(color: c.withValues(alpha: 0.4), blurRadius: 18, spreadRadius: -4)]
            : null,
      ),
      child: Icon(icon, size: size * 0.5, color: filled ? ProductColors.onBrand : c),
    );
  }
}

/// Soft radial green glow placed behind content (decorative, non-interactive).
class AmbientGlow extends StatelessWidget {
  const AmbientGlow({super.key, this.color, this.alignment = Alignment.topCenter, this.opacity = 0.22});

  final Color? color;
  final Alignment alignment;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final c = color ?? ProductColors.brandPrimary;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: alignment,
            radius: 0.9,
            colors: [c.withValues(alpha: opacity), c.withValues(alpha: 0)],
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Logo mark with a glow behind it.
class GlowMark extends StatelessWidget {
  const GlowMark({super.key, required this.child, this.size = 96});

  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: ProductColors.brandPrimary.withValues(alpha: 0.35),
            blurRadius: size * 0.7,
            spreadRadius: size * 0.05,
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Progress state of one [TimelineStep].
enum StepProgress { pending, current, complete, blocked }

class TimelineStep {
  const TimelineStep({
    required this.title,
    required this.body,
    this.progress = StepProgress.pending,
  });

  final String title;
  final String body;
  final StepProgress progress;
}

/// Vertical numbered steps joined by a connector line. Current, complete and
/// blocked steps are visually and semantically distinct. Text wraps freely;
/// the marker column is fixed so nothing can overflow horizontally.
class StepTimeline extends StatelessWidget {
  const StepTimeline({super.key, required this.steps});

  final List<TimelineStep> steps;

  static String labelFor(StepProgress p) => switch (p) {
        StepProgress.complete => 'Done',
        StepProgress.current => 'Now',
        StepProgress.blocked => 'Blocked',
        StepProgress.pending => 'Next',
      };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          Semantics(
            container: true,
            label:
                'Step ${i + 1} of ${steps.length}, ${labelFor(steps[i].progress)}: ${steps[i].title}',
            child: ExcludeSemantics(
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 36,
                      child: Column(
                        children: [
                          _StepMarker(index: i + 1, progress: steps[i].progress),
                          if (i < steps.length - 1)
                            Expanded(
                              child: Container(
                                width: 2,
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                color: steps[i].progress == StepProgress.complete
                                    ? ProductColors.brandPrimary
                                        .withValues(alpha: 0.5)
                                    : Colors.white.withValues(alpha: 0.10),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: ProductSpacing.x3),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                            bottom: i < steps.length - 1 ? ProductSpacing.x4 : 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: ProductSpacing.x2,
                              runSpacing: ProductSpacing.x1,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                      maxWidth: double.infinity),
                                  child: Text(steps[i].title,
                                      style: t.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: steps[i].progress ==
                                                  StepProgress.pending
                                              ? ProductColors.textSecondary
                                              : ProductColors.textPrimary)),
                                ),
                                if (steps[i].progress == StepProgress.current ||
                                    steps[i].progress == StepProgress.blocked)
                                  NeonPill(
                                    label: labelFor(steps[i].progress),
                                    color: steps[i].progress ==
                                            StepProgress.blocked
                                        ? ProductColors.error
                                        : ProductColors.brandPrimary,
                                  ),
                              ],
                            ),
                            const SizedBox(height: ProductSpacing.x1),
                            Text(steps[i].body, style: t.bodyMedium),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _StepMarker extends StatelessWidget {
  const _StepMarker({required this.index, required this.progress});

  final int index;
  final StepProgress progress;

  @override
  Widget build(BuildContext context) {
    final (Color c, Widget child, bool filled) = switch (progress) {
      StepProgress.complete => (
          ProductColors.brandPrimary,
          const Icon(Icons.check_rounded, size: 20, color: ProductColors.onBrand),
          true
        ),
      StepProgress.blocked => (
          ProductColors.error,
          const Icon(Icons.block_rounded, size: 18, color: ProductColors.error),
          false
        ),
      StepProgress.current => (
          ProductColors.brandPrimary,
          Text('$index',
              style: const TextStyle(
                  color: ProductColors.brandPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 15)),
          false
        ),
      StepProgress.pending => (
          ProductColors.textMuted,
          Text('$index',
              style: const TextStyle(
                  color: ProductColors.textMuted,
                  fontWeight: FontWeight.w800,
                  fontSize: 15)),
          false
        ),
    };
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: filled ? c : c.withValues(alpha: 0.14),
        border: Border.all(color: c.withValues(alpha: filled ? 0 : 0.45)),
        boxShadow: progress == StepProgress.current
            ? [BoxShadow(color: c.withValues(alpha: 0.3), blurRadius: 14, spreadRadius: -4)]
            : null,
      ),
      child: child,
    );
  }
}

/// Number of character kinds (lower, upper, digit, symbol) in [value].
int passwordKinds(String value) =>
    (RegExp(r'[a-z]').hasMatch(value) ? 1 : 0) +
    (RegExp(r'[A-Z]').hasMatch(value) ? 1 : 0) +
    (RegExp(r'[0-9]').hasMatch(value) ? 1 : 0) +
    (RegExp(r'[^A-Za-z0-9]').hasMatch(value) ? 1 : 0);

/// 0 (empty) .. 4 (strong). Presentation heuristic mirroring the server rule
/// (min length + at least three character kinds); the server decides.
int passwordStrength(String value, {int minLength = 14}) {
  if (value.isEmpty) return 0;
  final kinds = passwordKinds(value);
  if (value.length < minLength) return kinds >= 3 ? 2 : 1;
  if (kinds < 3) return 2;
  return kinds == 3 ? 3 : 4;
}

/// Four-segment strength bar with a text label (never colour alone).
class PasswordStrengthMeter extends StatelessWidget {
  const PasswordStrengthMeter({super.key, required this.strength});

  /// 0..4
  final int strength;

  @override
  Widget build(BuildContext context) {
    final label = switch (strength) {
      0 => 'Enter a password',
      1 => 'Weak',
      2 => 'Fair',
      3 => 'Good',
      _ => 'Strong',
    };
    final color = switch (strength) {
      <= 1 => ProductColors.error,
      2 => ProductColors.warning,
      _ => ProductColors.success,
    };
    return Semantics(
      label: 'Password strength: $label',
      child: ExcludeSemantics(
        child: Row(
          children: [
            for (var i = 0; i < 4; i++) ...[
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 6,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: i < strength
                        ? color
                        : Colors.white.withValues(alpha: 0.10),
                  ),
                ),
              ),
              if (i < 3) const SizedBox(width: 4),
            ],
            const SizedBox(width: ProductSpacing.x3),
            Flexible(
              flex: 0,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: color, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
