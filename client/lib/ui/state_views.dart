import 'package:flutter/material.dart';

import 'dark_kit.dart';
import 'product_theme.dart';

/// The one place that defines how every non-happy-path looks:
/// loading (skeleton), empty, error (with retry), offline / stale.
/// All variants scroll-safe: they never assume a fixed height.

enum ViewKind { loading, empty, error, offline }

/// Full-width state card used inside scrolling pages.
class StateView extends StatelessWidget {
  const StateView({
    super.key,
    required this.kind,
    this.title,
    this.message,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  const StateView.loading({Key? key, this.title, this.compact = false})
      : kind = ViewKind.loading,
        message = null,
        icon = null,
        actionLabel = null,
        onAction = null,
        super(key: key);

  const StateView.empty({
    Key? key,
    required String this.title,
    required String this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  })  : kind = ViewKind.empty,
        super(key: key);

  const StateView.error({
    Key? key,
    this.title = 'Something went wrong',
    this.message = 'Please try again. Your saved data is safe on this phone.',
    this.actionLabel = 'Try again',
    this.onAction,
    this.compact = false,
  })  : kind = ViewKind.error,
        icon = Icons.error_outline_rounded,
        super(key: key);

  const StateView.offline({
    Key? key,
    this.title = 'You are offline',
    this.message = 'Showing what is saved on this phone. It will update when you reconnect.',
    this.actionLabel,
    this.onAction,
    this.compact = false,
  })  : kind = ViewKind.offline,
        icon = Icons.cloud_off_outlined,
        super(key: key);

  final ViewKind kind;
  final String? title;
  final String? message;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (kind == ViewKind.loading) return SkeletonList(compact: compact);
    final t = Theme.of(context).textTheme;
    final tone = switch (kind) {
      ViewKind.error => ProductColors.error,
      ViewKind.offline => ProductColors.warning,
      _ => ProductColors.brandPrimary,
    };
    return Semantics(
      container: true,
      liveRegion: kind == ViewKind.error,
      child: GlassCard(
        padding: EdgeInsets.all(compact ? ProductSpacing.x4 : ProductSpacing.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(shape: BoxShape.circle, color: tone.withValues(alpha: 0.14)),
              child: Padding(
                padding: EdgeInsets.all(compact ? 10 : 16),
                child: Icon(icon, size: compact ? 24 : 32, color: tone),
              ),
            ),
            SizedBox(height: compact ? ProductSpacing.x2 : ProductSpacing.x4),
            if (title != null)
              Text(title!, style: t.titleLarge, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: ProductSpacing.x1),
              Text(message!, style: t.bodyMedium, textAlign: TextAlign.center),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: ProductSpacing.x4),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Slim inline banner (not a full card) for "stale data" / "offline" strips.
class StatusStrip extends StatelessWidget {
  const StatusStrip({super.key, required this.message, this.icon = Icons.cloud_off_outlined, this.color});

  final String message;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? ProductColors.warning;
    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(ProductRadius.medium),
          border: Border.all(color: c.withValues(alpha: 0.3)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: ProductSpacing.x3, vertical: ProductSpacing.x2),
          child: Row(
            children: [
              Icon(icon, size: 18, color: c),
              const SizedBox(width: ProductSpacing.x2),
              Expanded(
                child: Text(message, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: ProductColors.textPrimary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shimmering placeholder block. Static when animations are disabled.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, this.height = 16, this.width, this.radius = 10});

  final double height;
  final double? width;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          color: Color.lerp(const Color(0xFF16201B), const Color(0xFF1F2C26), _c.value),
        ),
      ),
    );
  }
}

/// A few skeleton rows shaped like list cards.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.rows = 3, this.compact = false});

  final int rows;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: ExcludeSemantics(
        child: Column(
          children: [
            for (var i = 0; i < rows; i++) ...[
              GlassCard(
                padding: const EdgeInsets.all(ProductSpacing.x4),
                radius: ProductRadius.large,
                child: Row(
                  children: [
                    const SkeletonBox(height: 48, width: 48, radius: 24),
                    const SizedBox(width: ProductSpacing.x4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SkeletonBox(height: 12, width: 80),
                          const SizedBox(height: 8),
                          const SkeletonBox(height: 16),
                          if (!compact) ...[const SizedBox(height: 8), const SkeletonBox(height: 12, width: 140)],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (i < rows - 1) const SizedBox(height: ProductSpacing.x3),
            ],
          ],
        ),
      ),
    );
  }
}
