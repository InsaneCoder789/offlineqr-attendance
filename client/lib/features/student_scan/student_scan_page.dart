import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/attendance/attendance_qr_protocol.dart';
import '../../core/database/local_database.dart';
import '../../core/security/device_crypto.dart';
import '../../ui/kiit_components.dart';
import '../../ui/kiit_theme.dart';

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
  @override
  Widget build(BuildContext context) {
    final student = widget.database.getCurrentStudent();
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(KiitSpacing.x5),
          children: [
            Text(
              'Scan Attendance',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: KiitSpacing.x2),
            Text(
              student == null
                  ? 'Sync your KIIT account before scanning classroom attendance.'
                  : 'Signed attendance is captured on this phone first. Scan the live classroom QR from inside the app, then sync updates the faculty portal when the backend is reachable.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: KiitColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: KiitSpacing.x8),
            _ScanActionCard(
              title: 'Scan Attendance QR',
              description:
                  'Open the secure in-app scanner for the rotating classroom QR.',
              icon: Icons.qr_code_scanner_rounded,
              onTap: _openScanner,
            ),
            const SizedBox(height: KiitSpacing.x4),
            _ScanActionCard(
              title: 'Attendance Logger',
              description:
                  'View every local scan, proof state, sync attempt, and review flag.',
              icon: Icons.receipt_long_outlined,
              onTap: _openLogger,
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
    if (!mounted || result == null) return;
    final snackMessage = result.alreadyScanned
        ? 'Attendance already scanned for ${result.courseName}.'
        : result.synced
            ? 'Attendance marked for ${result.courseName} and updated.'
            : 'Attendance marked for ${result.courseName}. Sync pending.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(snackMessage),
      ),
    );
    setState(() {});
  }

  void _openLogger() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _AttendanceLoggerPage(database: widget.database),
      ),
    );
  }
}

class _ScanActionCard extends StatelessWidget {
  const _ScanActionCard({
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(KiitRadius.large),
        onTap: onTap,
        child: KiitCard(
          padding: const EdgeInsets.all(KiitSpacing.x5),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: KiitColors.brandPrimarySoft,
                  borderRadius: BorderRadius.circular(KiitRadius.medium),
                ),
                child: Icon(icon, color: KiitColors.brandPrimaryStrong),
              ),
              const SizedBox(width: KiitSpacing.x4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: KiitSpacing.x1),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: KiitColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: KiitSpacing.x3),
              const Icon(Icons.chevron_right_rounded),
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
  double zoomScale = 0;

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
      statusText = 'Verifying secure attendance proof...';
    });
    try {
      await controller.stop();
      final created = await AttendanceClaimService(
        database: widget.database,
        keyStore: widget.keyStore,
      ).capture(raw);
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
      HapticFeedback.heavyImpact();
      if (mounted) {
        setState(() {
          processing = false;
          lastAttemptedRaw = null;
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
          statusText = 'Invalid QR code. Please scan the classroom QR.';
        });
        await controller.start();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: controller,
              fit: BoxFit.cover,
              errorBuilder: (context, error) {
                return _ScannerError(error: error.errorCode.name);
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
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.38),
              ),
            ),
            const _FullScreenScannerFrame(),
            Positioned(
              top: KiitSpacing.x4,
              left: KiitSpacing.x3,
              right: KiitSpacing.x3,
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Close scanner',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    color: Colors.white,
                    iconSize: 34,
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Torch',
                    onPressed: () async {
                      try {
                        await controller.toggleTorch();
                      } catch (_) {
                        if (mounted) {
                          setState(() => statusText =
                              'Torch is unavailable on this camera.');
                        }
                      }
                    },
                    icon: const Icon(Icons.flashlight_on_outlined),
                    color: KiitColors.brandPrimary,
                  ),
                ],
              ),
            ),
            Positioned(
              left: KiitSpacing.x5,
              right: KiitSpacing.x5,
              bottom: KiitSpacing.x5,
              child: _ScannerBottomInstruction(
                statusText: statusText,
                processing: processing,
                zoomScale: zoomScale,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FullScreenScannerFrame extends StatelessWidget {
  const _FullScreenScannerFrame();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(painter: _FullScreenScannerFramePainter()),
    );
  }
}

class _FullScreenScannerFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final frameWidth = size.width * 0.8;
    final frameHeight = (size.height * 0.44).clamp(280.0, 430.0);
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: frameWidth,
      height: frameHeight,
    );
    final ghost = Paint()
      ..color = KiitColors.brandPrimary.withValues(alpha: 0.18)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(26)),
      ghost,
    );

    final segments = [
      (KiitColors.brandPrimary, rect.topLeft, true, true),
      (KiitColors.brandPrimary, rect.topRight, false, true),
      (KiitColors.brandPrimary, rect.bottomLeft, true, false),
      (KiitColors.brandPrimary, rect.bottomRight, false, false),
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
    const radius = 36.0;
    const straight = 92.0;
    final horizontalStart = anchor + Offset(left ? radius : -radius, 0);
    final horizontalEnd = anchor + Offset(left ? straight : -straight, 0);
    final verticalStart = anchor + Offset(0, top ? radius : -radius);
    final verticalEnd = anchor + Offset(0, top ? straight : -straight);
    final cornerRect = Rect.fromCircle(
      center: anchor + Offset(left ? radius : -radius, top ? radius : -radius),
      radius: radius,
    );
    canvas.drawLine(horizontalStart, horizontalEnd, paint);
    canvas.drawLine(verticalStart, verticalEnd, paint);
    canvas.drawArc(
      cornerRect,
      left && top
          ? 3.14
          : !left && top
              ? 4.71
              : left && !top
                  ? 1.57
                  : 0,
      1.57,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ScannerBottomInstruction extends StatelessWidget {
  const _ScannerBottomInstruction({
    required this.statusText,
    required this.processing,
    required this.zoomScale,
  });

  final String statusText;
  final bool processing;
  final double zoomScale;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF343434).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          KiitSpacing.x5,
          KiitSpacing.x4,
          KiitSpacing.x5,
          KiitSpacing.x5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: KiitSpacing.x5),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (processing)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                else
                  const Icon(
                    Icons.qr_code_scanner_rounded,
                    color: KiitColors.brandPrimary,
                    size: 20,
                  ),
                const SizedBox(width: KiitSpacing.x2),
                Flexible(
                  child: Text(
                    processing ? 'Marking attendance' : 'Scan Attendance QR',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: KiitColors.brandPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: KiitSpacing.x2),
            Text(
              statusText,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFFD7D7D7),
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: KiitSpacing.x2),
            Text(
              'Auto zoom ${(1 + zoomScale * 3).toStringAsFixed(1)}x',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: KiitColors.brandPrimary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttendanceLoggerPage extends StatelessWidget {
  const _AttendanceLoggerPage({required this.database});

  final LocalAttendanceDatabase database;

  @override
  Widget build(BuildContext context) {
    final entries = database.getRecentAttendanceLog(limit: 500);
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance Logger')),
      body: SafeArea(
        child: entries.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(KiitSpacing.x5),
                child: Center(
                  child: EmptyState(
                    title: 'No scans recorded',
                    message:
                        'Every attendance QR scan will appear here with its local proof and sync state.',
                    icon: Icons.receipt_long_outlined,
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(KiitSpacing.x4),
                itemBuilder: (context, index) {
                  return _LoggerDetailCard(entry: entries[index]);
                },
                separatorBuilder: (_, __) =>
                    const SizedBox(height: KiitSpacing.x3),
                itemCount: entries.length,
              ),
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
    return KiitCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: KiitSpacing.x2,
            runSpacing: KiitSpacing.x2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                entry.courseCode,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              StatusChip(label: display.$1, tone: display.$2),
            ],
          ),
          const SizedBox(height: KiitSpacing.x2),
          Text(
            '${entry.courseName} | ${entry.sectionCode}',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: KiitSpacing.x4),
          _LogField(
              label: 'Recorded', value: _formatDateTime(entry.recordedAt)),
          _LogField(label: 'Claim state', value: entry.claimState),
          _LogField(label: 'Sync state', value: display.$3),
          _LogField(label: 'Attempts', value: entry.attemptCount.toString()),
          if (entry.lastErrorCode != null)
            _LogField(label: 'Review code', value: entry.lastErrorCode!),
          _LogField(label: 'Proof ID', value: entry.proofId),
          _LogField(label: 'Session ID', value: entry.sessionId),
        ],
      ),
    );
  }

  (String, StatusTone, String) _displayState(AttendanceLogEntry entry) {
    if (entry.isServerAccepted) {
      return ('Server accepted', StatusTone.success, 'SERVER_ACCEPTED');
    }
    if (entry.syncState == 'SERVER_REJECTED') {
      return ('Needs review', StatusTone.error, 'SERVER_REJECTED');
    }
    if (entry.syncState == 'SYNCING') {
      return ('Syncing', StatusTone.info, 'SYNCING');
    }
    if (entry.syncState == 'RETRY_PENDING') {
      return ('Sync pending', StatusTone.warning, 'RETRY_PENDING');
    }
    return ('Stored locally', StatusTone.warning, entry.syncState);
  }

  String _formatDateTime(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    final day = parsed.day.toString().padLeft(2, '0');
    final month = parsed.month.toString().padLeft(2, '0');
    final hour = parsed.hour.toString().padLeft(2, '0');
    final minute = parsed.minute.toString().padLeft(2, '0');
    return '$day/$month/${parsed.year} $hour:$minute';
  }
}

class _LogField extends StatelessWidget {
  const _LogField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KiitSpacing.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: KiitColors.textMuted,
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: KiitColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _ScannerError extends StatelessWidget {
  const _ScannerError({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(KiitSpacing.x5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.videocam_off_outlined,
                color: Colors.white,
                size: 36,
              ),
              const SizedBox(height: KiitSpacing.x3),
              Text(
                'Camera unavailable',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: KiitSpacing.x1),
              Text(
                'Scanner error: $error',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFE5E7EB),
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
