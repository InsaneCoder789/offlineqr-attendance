import 'package:flutter/material.dart';

import 'dark_kit.dart';
import 'dark_kit_extra_b.dart';
import 'product_theme.dart';
import 'state_views.dart';

const productLogoAsset = 'assets/branding/offlineqr_logo.png';

class ProductLogo extends StatelessWidget {
  const ProductLogo({super.key, this.height = 40});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      productLogoAsset,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => const _LogoFallback(),
    );
  }
}

class _LogoFallback extends StatelessWidget {
  const _LogoFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      width: 96,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: ProductColors.brandPrimary,
        borderRadius: BorderRadius.circular(ProductRadius.small),
      ),
      child: const Text(
        'OfflineQR',
        style: TextStyle(
          color: ProductColors.onBrand,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(ProductSpacing.x4),
    this.color,
    this.borderColor,
    this.shadow = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    if (color == null && borderColor == null) {
      return GlassCard(
        padding: padding,
        radius: 22,
        glow: shadow ? ProductColors.brandPrimary : null,
        child: child,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? ProductColors.surface,
        border: Border.all(color: borderColor ?? Colors.white.withValues(alpha: 0.07)),
        borderRadius: BorderRadius.circular(22),
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: ProductColors.brandPrimary.withValues(alpha: 0.16),
                  blurRadius: 32,
                  spreadRadius: -6,
                ),
              ]
            : null,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class ProductPageHeader extends StatelessWidget {
  const ProductPageHeader({
    super.key,
    required this.title,
    required this.description,
    this.trailing,
  });

  final String title;
  final String description;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                    ),
              ),
              const SizedBox(height: ProductSpacing.x2),
              Text(
                description,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: ProductColors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: ProductSpacing.x3),
          trailing!,
        ],
      ],
    );
  }
}

class ProductNoticeBanner extends StatelessWidget {
  const ProductNoticeBanner({
    super.key,
    required this.title,
    required this.message,
    this.tone = StatusTone.info,
    this.action,
  });

  final String title;
  final String message;
  final StatusTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = switch (tone) {
      StatusTone.success => (ProductColors.success, ProductColors.success.withValues(alpha: 0.12)),
      StatusTone.warning => (ProductColors.warning, ProductColors.warning.withValues(alpha: 0.12)),
      StatusTone.error => (ProductColors.error, ProductColors.error.withValues(alpha: 0.12)),
      StatusTone.info => (ProductColors.info, ProductColors.info.withValues(alpha: 0.12)),
      StatusTone.neutral => (ProductColors.textSecondary, Colors.white.withValues(alpha: 0.06)),
    };
    final icon = switch (tone) {
      StatusTone.success => Icons.check_circle_outline_rounded,
      StatusTone.warning => Icons.cloud_off_outlined,
      StatusTone.error => Icons.error_outline_rounded,
      StatusTone.info => Icons.info_outline_rounded,
      StatusTone.neutral => Icons.notifications_none_rounded,
    };
    return Semantics(
      container: true,
      liveRegion: tone == StatusTone.error,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(ProductSpacing.x4),
        decoration: BoxDecoration(
          color: palette.$2,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.$1.withValues(alpha: 0.32)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconChip(icon: icon, size: 36, color: palette.$1),
            const SizedBox(width: ProductSpacing.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: palette.$1,
                        ),
                  ),
                  const SizedBox(height: ProductSpacing.x1),
                  // Messages can be long server errors: wrap, never clip.
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: ProductColors.textSecondary,
                        ),
                  ),
                  if (action != null) ...[
                    const SizedBox(height: ProductSpacing.x3),
                    action!,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Flat 60dp+ list row: icon chip, one-line title, one-line subtitle and an
/// optional trailing widget. Lives inside a [ProductSection] (or any card).
/// Rows are tappable only when [onTap] is set. Never overflows: text is
/// ellipsized and the row grows with text scale instead of clipping.
class ProductListTile extends StatelessWidget {
  const ProductListTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.iconColor,
    this.titleColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? iconColor;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final end = trailing ??
        (onTap == null
            ? null
            : const Icon(Icons.chevron_right_rounded,
                color: ProductColors.textMuted));
    return Semantics(
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: ProductSpacing.x4, vertical: ProductSpacing.x2),
            child: Row(
              children: [
                IconChip(icon: icon, size: 36, color: iconColor),
                const SizedBox(width: ProductSpacing.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: titleColor ?? ProductColors.textPrimary),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodyMedium,
                        ),
                    ],
                  ),
                ),
                if (end != null) ...[
                  const SizedBox(width: ProductSpacing.x2),
                  end,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small uppercase caption above a [ProductSection].
class ProductSectionLabel extends StatelessWidget {
  const ProductSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
          left: ProductSpacing.x1, bottom: ProductSpacing.x2),
      child: Text(
        text.toUpperCase(),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: ProductColors.textMuted,
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}

/// A glass card holding hairline-separated rows, with an optional label.
class ProductSection extends StatelessWidget {
  const ProductSection({super.key, this.label, required this.children});

  final String? label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(const Divider(height: 1, indent: 64));
      rows.add(children[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null) ProductSectionLabel(label!),
        GlassCard(
          padding: const EdgeInsets.symmetric(vertical: ProductSpacing.x1),
          radius: 24,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Material(
              color: Colors.transparent,
              child: Column(children: rows),
            ),
          ),
        ),
      ],
    );
  }
}

/// Stand-alone tappable card version of [ProductListTile].
class ProductActionTile extends StatelessWidget {
  const ProductActionTile({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      radius: 22,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Material(
          color: Colors.transparent,
          child: ProductListTile(
            icon: icon,
            title: title,
            subtitle: description,
            onTap: onTap,
            trailing: const Icon(Icons.arrow_forward_rounded,
                color: ProductColors.textMuted),
          ),
        ),
      ),
    );
  }
}

class ProductSoftPanel extends StatelessWidget {
  const ProductSoftPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(ProductSpacing.x4),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ProductColors.brandPrimarySubtle,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ProductColors.brandPrimary.withValues(alpha: 0.14)),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    this.icon,
    this.tone = StatusTone.neutral,
  });

  final String label;
  final IconData? icon;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = switch (tone) {
      StatusTone.success => (ProductColors.success, ProductColors.success.withValues(alpha: 0.12)),
      StatusTone.warning => (ProductColors.warning, ProductColors.warning.withValues(alpha: 0.12)),
      StatusTone.error => (ProductColors.error, ProductColors.error.withValues(alpha: 0.12)),
      StatusTone.info => (ProductColors.info, ProductColors.info.withValues(alpha: 0.12)),
      StatusTone.neutral => (ProductColors.textSecondary, Colors.white.withValues(alpha: 0.06)),
    };
    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: ProductSpacing.x3,
          vertical: ProductSpacing.x2,
        ),
        decoration: BoxDecoration(
          color: colors.$2,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: colors.$1.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: colors.$1),
              const SizedBox(width: ProductSpacing.x2),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.$1,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum StatusTone { neutral, success, warning, error, info }

class SyncStatus extends StatelessWidget {
  const SyncStatus({
    super.key,
    required this.label,
    this.syncing = false,
    this.offline = false,
  });

  final String label;
  final bool syncing;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    return StatusChip(
      label: label,
      icon: syncing
          ? Icons.sync
          : offline
              ? Icons.cloud_off_outlined
              : Icons.check_circle_outline,
      tone: offline
          ? StatusTone.warning
          : syncing
              ? StatusTone.info
              : StatusTone.success,
    );
  }
}

/// Thin wrapper over [StateView.empty]; kept for its widget `action` slot.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final view = StateView.empty(title: title, message: message, icon: icon);
    if (action == null) return view;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        view,
        const SizedBox(height: ProductSpacing.x3),
        Center(child: action!),
      ],
    );
  }
}

class ClassesOverSticker extends StatelessWidget {
  const ClassesOverSticker({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 86.0 : 118.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            bottom: size * 0.15,
            child: Transform.rotate(
              angle: -0.08,
              child: Container(
                width: size * 0.68,
                height: size * 0.24,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E3A5F),
                  borderRadius: BorderRadius.circular(ProductRadius.small),
                  border: Border.all(color: const Color(0xFF4C86D6)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: size * 0.08,
            child: Transform.rotate(
              angle: 0.06,
              child: Container(
                width: size * 0.72,
                height: size * 0.24,
                decoration: BoxDecoration(
                  color: const Color(0xFF1F3B22),
                  borderRadius: BorderRadius.circular(ProductRadius.small),
                  border: Border.all(color: const Color(0xFF3F8A4D)),
                ),
              ),
            ),
          ),
          Positioned(
            top: size * 0.12,
            child: Container(
              width: size * 0.58,
              height: size * 0.58,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2412),
                borderRadius: BorderRadius.circular(ProductRadius.medium),
                border: Border.all(color: const Color(0xFFF5B84A), width: 1.4),
              ),
              child: CustomPaint(painter: _CalendarFacePainter()),
            ),
          ),
          Positioned(
            right: size * 0.05,
            top: size * 0.3,
            child: Transform.rotate(
              angle: 0.14,
              child: Container(
                width: size * 0.4,
                padding: EdgeInsets.all(compact ? 4 : 6),
                decoration: BoxDecoration(
                  color: ProductColors.brandPrimarySoft,
                  borderRadius: BorderRadius.circular(ProductRadius.small),
                  border: Border.all(color: ProductColors.brandPrimary),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Classes\nare over',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: ProductColors.brandPrimary,
                      fontSize: compact ? 8 : 10,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarFacePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final binding = Paint()
      ..color = const Color(0xFFF5B84A)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final face = Paint()
      ..color = ProductColors.textPrimary
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        Offset(size.width * 0.24, 0), Offset(size.width * 0.24, 8), binding);
    canvas.drawLine(
        Offset(size.width * 0.76, 0), Offset(size.width * 0.76, 8), binding);
    canvas.drawCircle(Offset(size.width * 0.34, size.height * 0.42), 1.8, face);
    canvas.drawCircle(Offset(size.width * 0.66, size.height * 0.42), 1.8, face);
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(size.width * 0.5, size.height * 0.55),
        width: size.width * 0.24,
        height: size.height * 0.18,
      ),
      0.25,
      2.64,
      false,
      face,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class CuteEmptyState extends StatelessWidget {
  const CuteEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.action,
  });

  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showSticker =
            !constraints.hasBoundedHeight || constraints.maxHeight >= 250;
        final body = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showSticker) ...[
                const ClassesOverSticker(),
                const SizedBox(height: ProductSpacing.x4),
              ],
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
              ),
              const SizedBox(height: ProductSpacing.x2),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: ProductColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              if (action != null) ...[
                const SizedBox(height: ProductSpacing.x4),
                action!,
              ],
            ],
          );
        return ProductSoftPanel(
          padding: const EdgeInsets.all(ProductSpacing.x5),
          child: constraints.hasBoundedHeight
              ? SingleChildScrollView(child: body)
              : body,
        );
      },
    );
  }
}

class ProductNotFoundPage extends StatelessWidget {
  const ProductNotFoundPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(ProductSpacing.x5),
            child: CuteEmptyState(
              title: 'Page not found',
              message:
                  'This screen is not available offline. Return to your timetable and continue from there.',
              action: FilledButton.icon(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.calendar_today_outlined),
                label: const Text('Back to app'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AttendanceProgress extends StatelessWidget {
  const AttendanceProgress({
    super.key,
    required this.percentage,
    this.height = 8,
  });

  final double percentage;
  final double height;

  @override
  Widget build(BuildContext context) {
    final value = (percentage / 100).clamp(0.0, 1.0);
    final color = percentage >= 75
        ? ProductColors.present
        : percentage >= 65
            ? ProductColors.warning
            : ProductColors.absent;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        minHeight: height,
        value: value,
        color: color,
        backgroundColor: Colors.white.withValues(alpha: 0.08),
      ),
    );
  }
}
