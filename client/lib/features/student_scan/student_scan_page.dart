import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/attendance/attendance_qr_protocol.dart';
import '../../core/database/local_database.dart';
import '../../core/security/device_crypto.dart';
import '../../core/sync/background_sync.dart';
import '../../ui/dark_kit.dart';
import '../../ui/dark_kit_extra_a.dart';
import '../../ui/dark_kit_extra_b.dart';
import '../../ui/product_theme.dart';
import '../../ui/responsive.dart';
import '../../ui/state_views.dart';

const String _reviewAdvice =
    'What to do: scan the live QR again, or ask your faculty to mark you present. Your other scans are not affected.';

String _formatDateTime(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  final p =
      parsed.isUtc ? parsed.add(const Duration(hours: 5, minutes: 30)) : parsed;
  final day = p.day.toString().padLeft(2, '0');
  final month = p.month.toString().padLeft(2, '0');
  final hour = p.hour.toString().padLeft(2, '0');
  final minute = p.minute.toString().padLeft(2, '0');
  return '$day/$month/${p.year} $hour:$minute';
}

class StudentScanPage extends StatefulWidget {
  const StudentScanPage({
    super.key,
    required this.database,
    required this.keyStore,
    this.onAttendanceRecorded,
  });

  final LocalAttendanceDatabase database;
  final DeviceKeyStore keyStore;
  final Future<bool> Function()? onAttendanceRecorded;

  @override
  State<StudentScanPage> createState() => _StudentScanPageState();
}

class _StudentScanPageState extends State<StudentScanPage> {
  StudentProfile? _student;
  List<AttendanceLogEntry> _entries = const [];
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant StudentScanPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.database != widget.database) _load();
  }

  void _load() {
    try {
      _student = widget.database.getCurrentStudent();
      _entries = widget.database.getRecentAttendanceLog(limit: 50);
      _error = null;
    } catch (error) {
      _error = error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final student = _student;
    final entries = _entries;
    final recent = entries.take(3).toList();
    final failed = entries.where((e) => e.hasDiscrepancy).length;
    final pending =
        entries.where((e) => !e.isServerAccepted && !e.hasDiscrepancy).length;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: AdaptivePage(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: ProductSpacing.x4),
              child: Text('Scan',
                  style: text.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.2,
                      height: 1.05)),
            ),
            const SizedBox(height: 4),
            Text(
              student == null
                  ? 'Sync your account before scanning a classroom QR.'
                  : 'Your proof is saved on this phone first, then sent automatically.',
              style:
                  text.bodyLarge?.copyWith(color: ProductColors.textSecondary),
            ),
            const SizedBox(height: ProductSpacing.x5),
            _ScanHero(enabled: student != null, onTap: _openScanner),
            const SizedBox(height: ProductSpacing.x4),
            if (student != null && failed > 0) ...[
              _ReviewNote(count: failed),
              const SizedBox(height: ProductSpacing.x4),
            ],
            if (student != null && pending > 0) ...[
              _SyncNote(count: pending),
              const SizedBox(height: ProductSpacing.x4),
            ],
            Row(
              children: [
                Expanded(
                  child: Text('Recent scans',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800, letterSpacing: -0.6)),
                ),
                TextButton(
                    onPressed: _openLogger, child: const Text('See all')),
              ],
            ),
            const SizedBox(height: ProductSpacing.x2),
            if (_error != null)
              StateView.error(
                compact: true,
                title: 'Could not read your scans',
                message: 'Your saved scans are safe on this phone.',
                onAction: () => setState(_load),
              )
            else if (recent.isEmpty)
              const StateView.empty(
                compact: true,
                icon: Icons.qr_code_2_rounded,
                title: 'No scans yet',
                message:
                    'No scans yet. Your scans will appear here with their sync status.',
              )
            else
              GlassCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var index = 0; index < recent.length; index++) ...[
                      Reveal(
                          index: index,
                          child: _RecentScanRow(
                              entry: recent[index], onTap: _openLogger)),
                      if (index < recent.length - 1)
                        Divider(
                            height: 1,
                            color: Colors.white.withValues(alpha: 0.06)),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openScanner() async {
    final result = await Navigator.of(context).push<_ScanCompletion>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _AttendanceScannerRoute(
          database: widget.database,
          keyStore: widget.keyStore,
          onAttendanceRecorded: widget.onAttendanceRecorded,
        ),
      ),
    );
    if (!mounted) return;
    setState(_load);
    if (result == null) return;
    final kind = result.alreadyScanned
        ? ScanResultKind.alreadyScanned
        : result.synced
            ? ScanResultKind.success
            : ScanResultKind.savedOffline;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: ProductColors.surface,
      builder: (_) =>
          ScanResultSheet(kind: kind, courseName: result.courseName),
    );
  }

  void _openLogger() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ScanHistoryPage(database: widget.database),
      ),
    );
  }
}

class _ScanHero extends StatefulWidget {
  const _ScanHero({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_ScanHero> createState() => _ScanHeroState();
}

class _ScanHeroState extends State<_ScanHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2400));
  bool _animating = false;

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _sync(bool reduce) {
    final want = widget.enabled && !reduce;
    if (want == _animating) return;
    _animating = want;
    if (want) {
      _pulse.repeat(count: 4); // finite so the screen settles and saves battery
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final reduce = MediaQuery.of(context).disableAnimations;
    _sync(reduce);
    final enabled = widget.enabled;
    final tone = enabled ? ProductColors.brandPrimary : ProductColors.textMuted;
    final media = MediaQuery.of(context);
    final short = media.size.height < 560;
    final scale = media.textScaler.scale(14) / 14;
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Scan attendance QR',
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? widget.onTap : null,
          child: NeonHero(
            padding:
                EdgeInsets.all(short ? ProductSpacing.x4 : ProductSpacing.x6),
            child: LayoutBuilder(builder: (context, c) {
              final horizontal = short && c.maxWidth >= 480;
              final dial = horizontal
                  ? 132.0
                  : (c.maxWidth < 240 || scale > 1.6
                      ? 124.0
                      : (short ? 148.0 : 188.0));
              final art = _pulseDial(dial, tone, enabled, reduce);
              final copy = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: horizontal
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: [
                  Text('Scan attendance QR',
                      textAlign:
                          horizontal ? TextAlign.start : TextAlign.center,
                      style: text.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                          color: enabled
                              ? ProductColors.textPrimary
                              : ProductColors.textSecondary)),
                  const SizedBox(height: ProductSpacing.x1),
                  Text(
                    enabled
                        ? 'Point your camera at the code on the classroom screen.'
                        : 'Scanning is off until this phone is signed in and synced once.',
                    textAlign: horizontal ? TextAlign.start : TextAlign.center,
                    style: text.bodyMedium
                        ?.copyWith(color: ProductColors.textSecondary),
                  ),
                  const SizedBox(height: ProductSpacing.x4),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: enabled
                          ? ProductColors.brandPrimary
                          : ProductColors.border,
                      borderRadius: BorderRadius.circular(99),
                      boxShadow: [
                        if (enabled)
                          BoxShadow(
                              color: ProductColors.brandPrimary
                                  .withValues(alpha: 0.4),
                              blurRadius: 24,
                              spreadRadius: -4),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: ProductSpacing.x5,
                          vertical: ProductSpacing.x3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                              enabled
                                  ? Icons.center_focus_strong_rounded
                                  : Icons.lock_outline_rounded,
                              size: 20,
                              color: enabled
                                  ? ProductColors.onBrand
                                  : ProductColors.textMuted),
                          const SizedBox(width: ProductSpacing.x2),
                          Flexible(
                            child: Text(
                                enabled ? 'Open scanner' : 'Sync required',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: text.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: enabled
                                        ? ProductColors.onBrand
                                        : ProductColors.textMuted)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
              if (horizontal) {
                return Row(children: [
                  art,
                  const SizedBox(width: ProductSpacing.x6),
                  Expanded(child: copy)
                ]);
              }
              return Column(children: [
                art,
                SizedBox(height: short ? ProductSpacing.x3 : ProductSpacing.x4),
                copy
              ]);
            }),
          ),
        ),
      ),
    );
  }

  Widget _pulseDial(double dial, Color tone, bool enabled, bool reduce) {
    final inner = dial * 0.6;
    return SizedBox(
      width: dial,
      height: dial,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final t = reduce ? 0.0 : _pulse.value;
          final glow = reduce ? 0.5 : 0.5 + 0.5 * math.sin(t * math.pi * 2);
          return CustomPaint(
            painter: _PulseRingPainter(
                t: t,
                color: tone,
                enabled: enabled && !reduce,
                innerRadius: inner / 2),
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tone.withValues(alpha: 0.14),
                  border:
                      Border.all(color: tone.withValues(alpha: 0.7), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: tone.withValues(
                          alpha: enabled ? 0.25 + 0.3 * glow : 0.0),
                      blurRadius: 28 + 14 * glow,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: SizedBox(
                  width: inner,
                  height: inner,
                  child: Icon(
                      enabled
                          ? Icons.qr_code_scanner_rounded
                          : Icons.lock_outline_rounded,
                      size: inner * 0.53,
                      color: tone),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PulseRingPainter extends CustomPainter {
  _PulseRingPainter(
      {required this.t,
      required this.color,
      required this.enabled,
      required this.innerRadius});

  final double t;
  final Color color;
  final bool enabled;
  final double innerRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color.withValues(alpha: 0.22);
    canvas.drawCircle(c, size.width / 2 - 2, base);
    if (!enabled) return;
    for (final phase in [0.0, 0.5]) {
      final p = (t + phase) % 1.0;
      final r = innerRadius + (size.width / 2 - innerRadius - 2) * p;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: 0.45 * (1 - p)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PulseRingPainter old) =>
      old.t != t ||
      old.color != color ||
      old.enabled != enabled ||
      old.innerRadius != innerRadius;
}

class _Note extends StatelessWidget {
  const _Note(
      {required this.color,
      required this.icon,
      required this.title,
      required this.body});

  final Color color;
  final IconData icon;
  final String? title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(ProductRadius.medium),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(ProductSpacing.x3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: ProductSpacing.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null)
                      Text(title!,
                          style: text.titleSmall?.copyWith(
                              color: color, fontWeight: FontWeight.w800)),
                    Text(body,
                        style: text.bodyMedium
                            ?.copyWith(color: ProductColors.textPrimary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SyncNote extends StatelessWidget {
  const _SyncNote({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return _Note(
      color: ProductColors.warning,
      icon: Icons.cloud_upload_outlined,
      title: null,
      body:
          '$count ${count == 1 ? 'scan is' : 'scans are'} waiting to sync. They are safe on this phone and will upload when you are online.',
    );
  }
}

class _ReviewNote extends StatelessWidget {
  const _ReviewNote({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return _Note(
      color: ProductColors.error,
      icon: Icons.error_outline_rounded,
      title: '$count ${count == 1 ? 'scan needs' : 'scans need'} review',
      body:
          'The server did not accept ${count == 1 ? 'it' : 'them'}. $_reviewAdvice',
    );
  }
}

class _RecentScanRow extends StatelessWidget {
  const _RecentScanRow({required this.entry, required this.onTap});

  final AttendanceLogEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final accepted = entry.isServerAccepted;
    final failed = entry.hasDiscrepancy;
    final color = failed
        ? ProductColors.error
        : accepted
            ? ProductColors.success
            : ProductColors.warning;
    final label = failed
        ? 'Needs review'
        : accepted
            ? 'Synchronized'
            : 'Stored locally';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(ProductSpacing.x4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(ProductRadius.medium),
              ),
              child: Icon(
                failed
                    ? Icons.error_outline_rounded
                    : accepted
                        ? Icons.check_rounded
                        : Icons.schedule_rounded,
                color: color,
                size: 20,
              ),
            ),
            const SizedBox(width: ProductSpacing.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${entry.courseCode} · ${entry.sectionCode}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium
                        ?.copyWith(color: color, fontWeight: FontWeight.w700),
                  ),
                  Text(_formatDateTime(entry.recordedAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall),
                  if (failed) ...[
                    const SizedBox(height: ProductSpacing.x1),
                    if (entry.lastErrorCode != null)
                      Text('Code: ${entry.lastErrorCode}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall
                              ?.copyWith(color: ProductColors.textMuted)),
                    Text(_reviewAdvice,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall
                            ?.copyWith(color: ProductColors.textSecondary)),
                  ],
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Icon(Icons.chevron_right_rounded,
                  color: ProductColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scan result sheet
// ---------------------------------------------------------------------------

enum ScanResultKind { success, alreadyScanned, savedOffline, rejected }

/// Bottom sheet shown after a scan: success, already scanned, saved offline
/// (will sync later) or rejected with a reason and what to do next.
class ScanResultSheet extends StatelessWidget {
  const ScanResultSheet(
      {super.key, required this.kind, this.courseName, this.reason});

  final ScanResultKind kind;
  final String? courseName;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final course = (courseName == null || courseName!.trim().isEmpty)
        ? 'this class'
        : courseName!;
    final (Color tone, IconData icon, String title, String body, String? hint) =
        switch (kind) {
      ScanResultKind.success => (
          ProductColors.success,
          Icons.check_circle_rounded,
          'Attendance marked',
          'You are marked present for $course and it is already updated.',
          null,
        ),
      ScanResultKind.alreadyScanned => (
          ProductColors.info,
          Icons.task_alt_rounded,
          'Already scanned',
          'Your attendance for $course was already recorded. Nothing more to do.',
          null,
        ),
      ScanResultKind.savedOffline => (
          ProductColors.warning,
          Icons.cloud_upload_outlined,
          'Saved on this phone',
          'Attendance for $course is saved securely. It will upload automatically when you are online.',
          'You do not need to scan again.',
        ),
      ScanResultKind.rejected => (
          ProductColors.error,
          Icons.error_outline_rounded,
          'Code not accepted',
          reason ?? 'This QR code could not be used for attendance.',
          'What to do: hold steady on the live code on the classroom screen and scan again. If it keeps failing, tell your faculty.',
        ),
    };
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            ProductSpacing.x5, 0, ProductSpacing.x5, ProductSpacing.x5),
        child: Semantics(
          liveRegion: true,
          container: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: IconChip(icon: icon, color: tone, size: 64)),
              const SizedBox(height: ProductSpacing.x4),
              Text(title,
                  textAlign: TextAlign.center,
                  style: text.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              const SizedBox(height: ProductSpacing.x2),
              Text(body,
                  textAlign: TextAlign.center,
                  style: text.bodyLarge
                      ?.copyWith(color: ProductColors.textSecondary)),
              if (hint != null) ...[
                const SizedBox(height: ProductSpacing.x3),
                _Note(
                    color: tone,
                    icon: Icons.lightbulb_outline_rounded,
                    title: null,
                    body: hint),
              ],
              const SizedBox(height: ProductSpacing.x5),
              FilledButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Done')),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanCompletion {
  const _ScanCompletion({
    required this.courseName,
    required this.synced,
    required this.alreadyScanned,
  });

  final String courseName;
  final bool synced;
  final bool alreadyScanned;
}

// ---------------------------------------------------------------------------
// Scanner
// ---------------------------------------------------------------------------

class _AttendanceScannerRoute extends StatefulWidget {
  const _AttendanceScannerRoute({
    required this.database,
    required this.keyStore,
    required this.onAttendanceRecorded,
  });

  final LocalAttendanceDatabase database;
  final DeviceKeyStore keyStore;
  final Future<bool> Function()? onAttendanceRecorded;

  @override
  State<_AttendanceScannerRoute> createState() =>
      _AttendanceScannerRouteState();
}

class _AttendanceScannerRouteState extends State<_AttendanceScannerRoute> {
  final controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
    cameraResolution: const Size(1280, 720),
  );
  Timer? zoomTimer;
  bool processing = false;
  String? lastAttemptedRaw;
  String statusText = 'Scan the live classroom QR.';
  String? rejection;
  double zoomScale = 0;
  bool torchOn = false;
  bool torchFailed = false;

  @override
  void initState() {
    super.initState();
    zoomTimer = Timer.periodic(const Duration(seconds: 3), (_) => _stepZoom());
  }

  @override
  void dispose() {
    zoomTimer?.cancel();
    controller.dispose();
    super.dispose();
  }

  Future<void> _stepZoom() async {
    if (!mounted || processing) return;
    if (zoomScale >= 0.54) {
      zoomTimer?.cancel();
      return;
    }
    final next = zoomScale + 0.18;
    try {
      await controller.setZoomScale(next);
      if (mounted) {
        setState(() => zoomScale = next);
      }
    } catch (_) {
      zoomTimer?.cancel();
    }
  }

  Future<void> _process(String raw) async {
    if (raw.trim().isEmpty || raw.length > 16384 || processing) return;
    if (lastAttemptedRaw == raw) return;
    lastAttemptedRaw = raw;
    setState(() {
      processing = true;
      rejection = null;
      statusText = 'Verifying secure attendance proof...';
    });
    try {
      await controller.stop();
      final created = await AttendanceClaimService(
        database: widget.database,
        keyStore: widget.keyStore,
      ).capture(raw);
      unawaited(scheduleImmediateAttendanceSync());
      HapticFeedback.mediumImpact();
      final synced = created.alreadyScanned
          ? true
          : await widget.onAttendanceRecorded?.call() ?? false;
      if (!mounted) return;
      Navigator.of(context).pop(
        _ScanCompletion(
          courseName: created.courseName,
          synced: synced,
          alreadyScanned: created.alreadyScanned,
        ),
      );
    } on AttendanceQrException catch (exception) {
      assert(() {
        debugPrint('Attendance QR verification failed: ${exception.code}');
        return true;
      }());
      HapticFeedback.heavyImpact();
      if (mounted) {
        setState(() {
          processing = false;
          lastAttemptedRaw = null;
          rejection = exception.message;
          statusText = exception.message;
        });
        await controller.start();
      }
    } catch (_) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        setState(() {
          processing = false;
          lastAttemptedRaw = null;
          rejection = 'Invalid QR code. Please scan the classroom QR.';
          statusText = 'Invalid QR code. Please scan the classroom QR.';
        });
        await controller.start();
      }
    }
  }

  Future<void> _toggleTorch() async {
    try {
      await controller.toggleTorch();
      if (mounted) setState(() => torchOn = !torchOn);
    } catch (_) {
      if (mounted) {
        setState(() {
          torchFailed = true;
          torchOn = false;
          statusText = 'Torch is unavailable on this camera.';
        });
      }
    }
  }

  Future<void> _retryCamera() async {
    try {
      await controller.start();
    } catch (_) {
      // The error builder keeps showing the current problem.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ProductColors.background,
      body: SafeArea(
        child: ValueListenableBuilder<MobileScannerState>(
          valueListenable: controller,
          builder: (context, state, _) {
            final cameraProblem = state.error != null;
            final torchUnavailable = torchFailed ||
                (state.isInitialized &&
                    state.torchState == TorchState.unavailable);
            return Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: controller,
                  fit: BoxFit.cover,
                  placeholderBuilder: (context) => const ScannerCameraOverlay(
                      kind: ScannerCameraProblem.starting),
                  errorBuilder: (context, error) {
                    return ScannerCameraOverlay(
                      kind: ScannerCameraOverlay.kindForCode(
                          error.errorCode.name),
                      detail: error.errorCode.name,
                      onRetry: _retryCamera,
                    );
                  },
                  onDetect: (capture) {
                    final raw = capture.barcodes.isEmpty
                        ? null
                        : capture.barcodes.first.rawValue;
                    if (raw != null) {
                      _process(raw);
                    }
                  },
                ),
                if (!cameraProblem) ...[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.38),
                    ),
                  ),
                  _FullScreenScannerFrame(rejected: rejection != null),
                ],
                Positioned(
                  top: ProductSpacing.x4,
                  left: ProductSpacing.x3,
                  right: ProductSpacing.x3,
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Close scanner',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                        color: ProductColors.textPrimary,
                        style: IconButton.styleFrom(
                            backgroundColor: ProductColors.background
                                .withValues(alpha: 0.6)),
                        iconSize: 30,
                      ),
                      const Spacer(),
                      if (!cameraProblem)
                        IconButton(
                          tooltip: torchUnavailable
                              ? 'Torch unavailable on this camera'
                              : 'Torch',
                          onPressed: torchUnavailable ? null : _toggleTorch,
                          icon: Icon(torchOn
                              ? Icons.flashlight_on_rounded
                              : torchUnavailable
                                  ? Icons.flash_off_rounded
                                  : Icons.flashlight_off_outlined),
                          color: torchOn
                              ? ProductColors.onBrand
                              : ProductColors.textPrimary,
                          disabledColor: ProductColors.textMuted,
                          style: IconButton.styleFrom(
                            backgroundColor: torchOn
                                ? ProductColors.brandPrimary
                                : ProductColors.background
                                    .withValues(alpha: 0.6),
                          ),
                          iconSize: 28,
                        ),
                    ],
                  ),
                ),
                if (!cameraProblem)
                  Positioned(
                    left: ProductSpacing.x4,
                    right: ProductSpacing.x4,
                    bottom: ProductSpacing.x4,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: _ScannerBottomInstruction(
                          statusText: statusText,
                          processing: processing,
                          zoomScale: zoomScale,
                          rejected: rejection != null,
                          torchUnavailable: torchUnavailable,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FullScreenScannerFrame extends StatelessWidget {
  const _FullScreenScannerFrame({this.rejected = false});

  final bool rejected;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _FullScreenScannerFramePainter(
          color: rejected ? ProductColors.error : ProductColors.brandPrimary,
        ),
      ),
    );
  }
}

class _FullScreenScannerFramePainter extends CustomPainter {
  _FullScreenScannerFramePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final side = (size.shortestSide * 0.72).clamp(200.0, 380.0);
    final landscape = size.width > size.height;
    final rect = Rect.fromCenter(
      center: Offset(
          size.width / 2, landscape ? size.height * 0.46 : size.height * 0.40),
      width: side,
      height: landscape ? (size.height * 0.62).clamp(160.0, side) : side,
    );
    final ghost = Paint()
      ..color = color.withValues(alpha: 0.30)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(26)),
      ghost,
    );

    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(26)), glowPaint);

    final segments = [
      (color, rect.topLeft, true, true),
      (color, rect.topRight, false, true),
      (color, rect.bottomLeft, true, false),
      (color, rect.bottomRight, false, false),
    ];
    for (final segment in segments) {
      _drawCorner(
        canvas,
        color: segment.$1,
        anchor: segment.$2,
        left: segment.$3,
        top: segment.$4,
      );
    }
  }

  void _drawCorner(
    Canvas canvas, {
    required Color color,
    required Offset anchor,
    required bool left,
    required bool top,
  }) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const radius = 28.0;
    const straight = 64.0;
    final glow = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    final horizontalStart = anchor + Offset(left ? radius : -radius, 0);
    final horizontalEnd = anchor + Offset(left ? straight : -straight, 0);
    final verticalStart = anchor + Offset(0, top ? radius : -radius);
    final verticalEnd = anchor + Offset(0, top ? straight : -straight);
    final cornerRect = Rect.fromCircle(
      center: anchor + Offset(left ? radius : -radius, top ? radius : -radius),
      radius: radius,
    );
    for (final p in [glow, paint]) {
      canvas.drawLine(horizontalStart, horizontalEnd, p);
      canvas.drawLine(verticalStart, verticalEnd, p);
    }
    final startAngle = left && top
        ? 3.14
        : !left && top
            ? 4.71
            : left && !top
                ? 1.57
                : 0.0;
    for (final p in [glow, paint]) {
      canvas.drawArc(cornerRect, startAngle, 1.57, false, p);
    }
  }

  @override
  bool shouldRepaint(covariant _FullScreenScannerFramePainter old) =>
      old.color != color;
}

class _ScannerBottomInstruction extends StatelessWidget {
  const _ScannerBottomInstruction({
    required this.statusText,
    required this.processing,
    required this.zoomScale,
    this.rejected = false,
    this.torchUnavailable = false,
  });

  final String statusText;
  final bool processing;
  final double zoomScale;
  final bool rejected;
  final bool torchUnavailable;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final height = MediaQuery.of(context).size.height;
    final tone = rejected ? ProductColors.error : ProductColors.brandPrimary;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: math.max(120.0, height * 0.5)),
      child: GlassCard(
        radius: ProductRadius.hero + 4,
        glow: tone,
        tint: ProductColors.surfaceElevated,
        padding: const EdgeInsets.fromLTRB(ProductSpacing.x5, ProductSpacing.x3,
            ProductSpacing.x5, ProductSpacing.x4),
        child: SingleChildScrollView(
          child: Semantics(
            liveRegion: true,
            container: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: ProductSpacing.x3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (processing)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              ProductColors.brandPrimary),
                        ),
                      )
                    else
                      Icon(
                          rejected
                              ? Icons.error_outline_rounded
                              : Icons.qr_code_scanner_rounded,
                          color: tone,
                          size: 22),
                    const SizedBox(width: ProductSpacing.x2),
                    Flexible(
                      child: Text(
                        processing
                            ? 'Marking attendance'
                            : rejected
                                ? 'Code not accepted'
                                : 'Scan Attendance QR',
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleLarge?.copyWith(
                          color: tone,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: ProductSpacing.x2),
                Text(
                  statusText,
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyLarge?.copyWith(
                      color: ProductColors.textSecondary,
                      fontWeight: FontWeight.w600),
                ),
                if (rejected) ...[
                  const SizedBox(height: ProductSpacing.x1),
                  Text(
                    'What to do: hold steady on the live code on the classroom screen and try again.',
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall
                        ?.copyWith(color: ProductColors.textMuted),
                  ),
                ],
                if (height > 520) ...[
                  const SizedBox(height: ProductSpacing.x2),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: ProductSpacing.x2,
                    runSpacing: ProductSpacing.x1,
                    children: [
                      NeonPill(
                        label:
                            'Auto zoom ${(1 + zoomScale * 3).toStringAsFixed(1)}x',
                        icon: Icons.zoom_in_rounded,
                      ),
                      if (torchUnavailable)
                        const NeonPill(
                          label: 'Torch unavailable',
                          icon: Icons.flash_off_rounded,
                          color: ProductColors.warning,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Camera problem overlay
// ---------------------------------------------------------------------------

enum ScannerCameraProblem { starting, permissionDenied, unsupported, error }

/// Full-bleed explanation shown instead of the camera preview while it is
/// starting, or when it cannot run. No settings package: it explains where to
/// go and offers a retry.
class ScannerCameraOverlay extends StatelessWidget {
  const ScannerCameraOverlay(
      {super.key, required this.kind, this.detail, this.onRetry});

  final ScannerCameraProblem kind;

  /// Technical code (shown small, truncated).
  final String? detail;
  final VoidCallback? onRetry;

  static ScannerCameraProblem kindForCode(String code) {
    final normalized = code.toLowerCase();
    if (normalized.contains('permission')) {
      return ScannerCameraProblem.permissionDenied;
    }
    if (normalized.contains('unsupported')) {
      return ScannerCameraProblem.unsupported;
    }
    return ScannerCameraProblem.error;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (kind == ScannerCameraProblem.starting) {
      return ColoredBox(
        color: ProductColors.background,
        child: Center(
          child: Semantics(
            label: 'Starting camera',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                      strokeWidth: 3, color: ProductColors.brandPrimary),
                ),
                const SizedBox(height: ProductSpacing.x3),
                Text('Starting camera...',
                    style: text.bodyMedium, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
    }
    final (IconData icon, String title, String message, List<String> steps) =
        switch (kind) {
      ScannerCameraProblem.permissionDenied => (
          Icons.no_photography_outlined,
          'Camera access is off',
          'OfflineQR needs the camera to read the classroom QR. It never records or uploads photos.',
          const [
            'Open your phone Settings.',
            'Go to Apps, then OfflineQR, then Permissions.',
            'Set Camera to Allow.',
            'Come back here and tap Try again.',
          ],
        ),
      ScannerCameraProblem.unsupported => (
          Icons.videocam_off_outlined,
          'Scanning is not supported',
          'This device has no usable camera for secure QR scanning.',
          const [
            'Use a phone with a rear camera.',
            'Ask your faculty to mark your attendance instead.',
          ],
        ),
      _ => (
          Icons.videocam_off_outlined,
          'Camera unavailable',
          'The camera could not be started. Another app may be using it.',
          const [
            'Close other apps that use the camera.',
            'Tap Try again, or close the scanner and reopen it.',
          ],
        ),
    };
    return ColoredBox(
      color: ProductColors.background,
      child: LayoutBuilder(builder: (context, c) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              ProductSpacing.x5, 72, ProductSpacing.x5, ProductSpacing.x5),
          child: ConstrainedBox(
            constraints: BoxConstraints(
                minHeight: math.max(0, c.maxHeight - 72 - ProductSpacing.x5)),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Semantics(
                  container: true,
                  liveRegion: true,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(child: IconChip(icon: icon, size: 64)),
                      const SizedBox(height: ProductSpacing.x4),
                      Text(title,
                          textAlign: TextAlign.center,
                          style: text.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4)),
                      const SizedBox(height: ProductSpacing.x2),
                      Text(message,
                          textAlign: TextAlign.center, style: text.bodyMedium),
                      const SizedBox(height: ProductSpacing.x4),
                      GlassCard(
                        padding: const EdgeInsets.all(ProductSpacing.x4),
                        radius: ProductRadius.large,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < steps.length; i++)
                              Padding(
                                padding: EdgeInsets.only(
                                    bottom: i == steps.length - 1
                                        ? 0
                                        : ProductSpacing.x2),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 24,
                                      child: Text('${i + 1}.',
                                          style: text.bodyMedium?.copyWith(
                                              color: ProductColors.brandPrimary,
                                              fontWeight: FontWeight.w800)),
                                    ),
                                    Expanded(
                                      child: Text(steps[i],
                                          style: text.bodyMedium?.copyWith(
                                              color:
                                                  ProductColors.textPrimary)),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (onRetry != null) ...[
                        const SizedBox(height: ProductSpacing.x4),
                        FilledButton(
                            onPressed: onRetry, child: const Text('Try again')),
                      ],
                      if (detail != null) ...[
                        const SizedBox(height: ProductSpacing.x3),
                        Text('Code: $detail',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall
                                ?.copyWith(color: ProductColors.textMuted)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Scan history
// ---------------------------------------------------------------------------

class ScanHistoryPage extends StatefulWidget {
  const ScanHistoryPage({super.key, required this.database});

  final LocalAttendanceDatabase database;

  @override
  State<ScanHistoryPage> createState() => _ScanHistoryPageState();
}

class _ScanHistoryPageState extends State<ScanHistoryPage> {
  List<AttendanceLogEntry> _entries = const [];
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    try {
      _entries = widget.database.getRecentAttendanceLog(limit: 500);
      _error = null;
    } catch (error) {
      _error = error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final accepted = entries.where((e) => e.isServerAccepted).length;
    final review = entries.where((e) => e.hasDiscrepancy).length;
    final waiting = entries.length - accepted - review;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Scan history')),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, c) {
          final base = c.maxWidth >= Breakpoints.medium
              ? ProductSpacing.x6
              : ProductSpacing.x4;
          final side = ((c.maxWidth - 640) / 2).clamp(base, double.infinity);
          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: side),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const SizedBox(height: ProductSpacing.x4),
                    if (_error != null)
                      StateView.error(
                        title: 'Could not read your scans',
                        message: 'Your saved scans are safe on this phone.',
                        onAction: () => setState(_load),
                      )
                    else if (entries.isEmpty)
                      const StateView.empty(
                        icon: Icons.receipt_long_outlined,
                        title: 'No scans recorded',
                        message:
                            'Every scan appears here with its sync status.',
                      )
                    else ...[
                      Wrap(
                        spacing: ProductSpacing.x2,
                        runSpacing: ProductSpacing.x2,
                        children: [
                          NeonPill(
                              label: '$accepted synced',
                              color: ProductColors.success,
                              icon: Icons.check_rounded),
                          if (waiting > 0)
                            NeonPill(
                                label: '$waiting waiting',
                                color: ProductColors.warning,
                                icon: Icons.schedule_rounded),
                          if (review > 0)
                            NeonPill(
                                label: '$review need review',
                                color: ProductColors.error,
                                icon: Icons.error_outline_rounded),
                        ],
                      ),
                      if (review > 0) ...[
                        const SizedBox(height: ProductSpacing.x3),
                        _ReviewNote(count: review),
                      ],
                      const SizedBox(height: ProductSpacing.x4),
                      Text(
                          '${entries.length} ${entries.length == 1 ? 'scan' : 'scans'}',
                          style: text.labelMedium),
                      const SizedBox(height: ProductSpacing.x2),
                    ],
                  ]),
                ),
              ),
              if (entries.isNotEmpty && _error == null)
                SliverPadding(
                  padding:
                      EdgeInsets.fromLTRB(side, 0, side, ProductSpacing.x8),
                  sliver: SliverList.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.only(bottom: ProductSpacing.x3),
                      child: i < 10
                          ? Reveal(
                              index: i,
                              child: _LoggerDetailCard(entry: entries[i]))
                          : _LoggerDetailCard(entry: entries[i]),
                    ),
                  ),
                )
              else
                const SliverToBoxAdapter(
                    child: SizedBox(height: ProductSpacing.x8)),
            ],
          );
        }),
      ),
    );
  }
}

class _LoggerDetailCard extends StatelessWidget {
  const _LoggerDetailCard({required this.entry});

  final AttendanceLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final display = _displayState(entry);
    final text = Theme.of(context).textTheme;
    final failed = entry.hasDiscrepancy;
    return GlassCard(
      radius: 22,
      padding: const EdgeInsets.all(ProductSpacing.x4),
      tint: failed
          ? Color.lerp(ProductColors.surfaceElevated, ProductColors.error, 0.12)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: ProductSpacing.x2,
            runSpacing: ProductSpacing.x2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(entry.courseCode,
                  style: text.titleLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              NeonPill(label: display.$1, color: display.$2, icon: display.$4),
            ],
          ),
          const SizedBox(height: ProductSpacing.x1),
          Text('${entry.courseName} · ${entry.sectionCode}',
              style: text.bodyLarge,
              maxLines: 3,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: ProductSpacing.x1),
          Text(_formatDateTime(entry.recordedAt),
              style: text.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          if (failed) ...[
            const SizedBox(height: ProductSpacing.x2),
            const _Note(
                color: ProductColors.error,
                icon: Icons.help_outline_rounded,
                title: null,
                body: _reviewAdvice),
          ],
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: ProductSpacing.x2),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              title: Text('Details', style: text.labelLarge),
              children: [
                _LogField(label: 'Claim state', value: entry.claimState),
                _LogField(label: 'Sync state', value: display.$3),
                _LogField(
                    label: 'Attempts', value: entry.attemptCount.toString()),
                if (entry.lastErrorCode != null)
                  _LogField(label: 'Review code', value: entry.lastErrorCode!),
                _LogField(label: 'Proof ID', value: entry.proofId),
                _LogField(label: 'Session ID', value: entry.sessionId),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (String, Color, String, IconData) _displayState(AttendanceLogEntry entry) {
    if (entry.isServerAccepted) {
      return (
        'Server accepted',
        ProductColors.success,
        'SERVER_ACCEPTED',
        Icons.check_rounded
      );
    }
    if (entry.syncState == 'SERVER_REJECTED' ||
        entry.syncState == 'CONFLICT_REVIEW') {
      return (
        'Needs review',
        ProductColors.error,
        entry.syncState,
        Icons.error_outline_rounded
      );
    }
    if (entry.syncState == 'SYNCING') {
      return ('Syncing', ProductColors.info, 'SYNCING', Icons.sync_rounded);
    }
    if (entry.syncState == 'RETRY_PENDING') {
      return (
        'Sync pending',
        ProductColors.warning,
        'RETRY_PENDING',
        Icons.schedule_rounded
      );
    }
    return (
      'Stored locally',
      ProductColors.warning,
      entry.syncState,
      Icons.schedule_rounded
    );
  }
}

class _LogField extends StatelessWidget {
  const _LogField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: ProductSpacing.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: ProductColors.textMuted,
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: ProductColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}
