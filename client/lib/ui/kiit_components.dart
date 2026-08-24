import 'package:flutter/material.dart';

import 'kiit_theme.dart';

const kiitLogoAsset = 'assets/branding/kiit_logo.png';

class KiitLogo extends StatelessWidget {
  const KiitLogo({super.key, this.height = 40});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      kiitLogoAsset,
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
        color: KiitColors.brandPrimary,
        borderRadius: BorderRadius.circular(KiitRadius.small),
      ),
      child: const Text(
        'KIIT',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class KiitCard extends StatelessWidget {
  const KiitCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(KiitSpacing.x4),
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? KiitColors.surface,
        border: Border.all(color: KiitColors.border),
        borderRadius: BorderRadius.circular(KiitRadius.large),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class KiitSoftPanel extends StatelessWidget {
  const KiitSoftPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(KiitSpacing.x4),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: KiitColors.brandPrimarySubtle,
        borderRadius: BorderRadius.circular(KiitRadius.large),
        border: Border.all(color: KiitColors.border),
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
      StatusTone.success => (KiitColors.success, const Color(0xFFEAF7EE)),
      StatusTone.warning => (KiitColors.warning, const Color(0xFFFFF7E6)),
      StatusTone.error => (KiitColors.error, const Color(0xFFFFF0ED)),
      StatusTone.info => (KiitColors.info, const Color(0xFFEFF6FF)),
      StatusTone.neutral => (KiitColors.textSecondary, const Color(0xFFF1F5F3)),
    };
    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: KiitSpacing.x3,
          vertical: KiitSpacing.x2,
        ),
        decoration: BoxDecoration(
          color: colors.$2,
          borderRadius: BorderRadius.circular(KiitRadius.small),
          border: Border.all(color: colors.$1.withValues(alpha: 0.18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: colors.$1),
              const SizedBox(width: KiitSpacing.x2),
            ],
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
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
    return KiitCard(
      color: KiitColors.brandPrimarySubtle,
      child: Column(
        children: [
          Icon(icon, size: 32, color: KiitColors.brandPrimaryStrong),
          const SizedBox(height: KiitSpacing.x3),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: KiitSpacing.x2),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (action != null) ...[
            const SizedBox(height: KiitSpacing.x4),
            action!,
          ],
        ],
      ),
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
                  color: const Color(0xFFB7D7FF),
                  borderRadius: BorderRadius.circular(KiitRadius.small),
                  border: Border.all(color: const Color(0xFF5E8FD1)),
                  boxShadow: [
                    BoxShadow(
                      color: KiitColors.textPrimary.withValues(alpha: 0.08),
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
                  color: const Color(0xFFE5F6CF),
                  borderRadius: BorderRadius.circular(KiitRadius.small),
                  border: Border.all(color: const Color(0xFF7DAE57)),
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
                color: const Color(0xFFFFF5D9),
                borderRadius: BorderRadius.circular(KiitRadius.medium),
                border: Border.all(color: const Color(0xFFD9B86A), width: 1.4),
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
                width: size * 0.34,
                padding: EdgeInsets.all(compact ? 5 : 7),
                decoration: BoxDecoration(
                  color: KiitColors.brandPrimarySoft,
                  borderRadius: BorderRadius.circular(KiitRadius.small),
                  border: Border.all(color: KiitColors.brandPrimary),
                ),
                child: Text(
                  'Classes\nare over',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: KiitColors.brandPrimaryStrong,
                    fontSize: compact ? 8 : 10,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
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
      ..color = const Color(0xFFD9B86A)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final face = Paint()
      ..color = KiitColors.textPrimary
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
    return KiitSoftPanel(
      padding: const EdgeInsets.all(KiitSpacing.x5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ClassesOverSticker(),
          const SizedBox(height: KiitSpacing.x4),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: KiitSpacing.x2),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: KiitColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          if (action != null) ...[
            const SizedBox(height: KiitSpacing.x4),
            action!,
          ],
        ],
      ),
    );
  }
}

class KiitNotFoundPage extends StatelessWidget {
  const KiitNotFoundPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(KiitSpacing.x5),
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
        ? KiitColors.present
        : percentage >= 65
            ? KiitColors.warning
            : KiitColors.absent;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        minHeight: height,
        value: value,
        color: color,
        backgroundColor: KiitColors.divider,
      ),
    );
  }
}
