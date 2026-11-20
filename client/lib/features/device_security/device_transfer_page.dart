import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/database/local_database.dart';
import '../../core/security/device_registration_service.dart';
import '../../core/security/secure_device_key_store.dart';
import '../../ui/dark_kit.dart';
import '../../ui/dark_kit_extra_b.dart';
import '../../ui/product_components.dart';
import '../../ui/product_theme.dart';
import '../../ui/responsive.dart';
import '../../ui/state_views.dart';

/// Where the switch stands, derived from the local device projection.
enum TransferStage { start, awaitingIct, blocked, complete }

TransferStage transferStageFor(DeviceRegistrationProjection? projection) {
  if (projection == null) return TransferStage.start;
  final status = projection.status.toUpperCase();
  if (status.contains('REVOK') || status.contains('BLOCK')) {
    return TransferStage.blocked;
  }
  if (status == 'ACTIVE') return TransferStage.complete;
  return TransferStage.awaitingIct;
}

/// A device-bound private key must never be exported through a QR code.
/// Switching devices is created by the new phone and approved by ICT.
class DeviceTransferPage extends StatelessWidget {
  const DeviceTransferPage({
    super.key,
    required this.database,
    required this.keyStore,
    required this.service,
  });

  final LocalAttendanceDatabase database;
  final SecureStorageDeviceKeyStore keyStore;
  final DeviceRegistrationService service;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Switch Attendance Device')),
      body: SafeArea(
        child: DeviceTransferView(
          stage: transferStageFor(database.getDeviceProjection()),
          onScan: () async {
            final student = database.getCurrentStudent();
            if (student == null) return;
            final completed = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) => _DeviceActivationScanner(
                  studentId: student.id,
                  service: service,
                ),
              ),
            );
            if (completed == true && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text(
                        'This phone is now your active attendance device.')),
              );
              Navigator.of(context).pop();
            }
          },
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}

/// Presentation of the transfer page for a given [TransferStage].
class DeviceTransferView extends StatelessWidget {
  const DeviceTransferView({
    super.key,
    required this.stage,
    this.onScan,
    this.onBack,
  });

  final TransferStage stage;
  final VoidCallback? onScan;
  final VoidCallback? onBack;

  List<TimelineStep> get _steps {
    const titles = [
      'Open OfflineQR on the new phone',
      'Create a replacement request',
      'Wait for ICT approval',
    ];
    const bodies = [
      'Sign in with the same Institution account and choose Relink Lost or Reinstalled Phone.',
      'The new device creates a fresh protected key and submits its make, model, OS, and physical-device signal for review.',
      'ICT checks the device history, approves the request, then displays a five-minute activation QR. Scan it on this new phone to complete the switch.',
    ];
    final states = switch (stage) {
      TransferStage.start => const [
          StepProgress.current,
          StepProgress.pending,
          StepProgress.pending
        ],
      TransferStage.awaitingIct => const [
          StepProgress.complete,
          StepProgress.complete,
          StepProgress.current
        ],
      TransferStage.blocked => const [
          StepProgress.complete,
          StepProgress.complete,
          StepProgress.blocked
        ],
      TransferStage.complete => const [
          StepProgress.complete,
          StepProgress.complete,
          StepProgress.complete
        ],
    };
    return [
      for (var i = 0; i < 3; i++)
        TimelineStep(title: titles[i], body: bodies[i], progress: states[i]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(20));
    return AdaptivePage(
      children: [
        const SizedBox(height: ProductSpacing.x4),
        FadeSlideIn(
          child: NeonHero(
            padding: const EdgeInsets.all(ProductSpacing.x5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const GlowMark(
                  size: 56,
                  child: IconChip(
                      icon: Icons.admin_panel_settings_outlined,
                      size: 56,
                      filled: true),
                ),
                const SizedBox(height: ProductSpacing.x4),
                Text('ICT-approved device switch',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(letterSpacing: -0.6)),
                const SizedBox(height: ProductSpacing.x2),
                Text(
                  'Attendance credentials are bound to this phone and are never copied through a QR code. A new phone creates its own key, then ICT reviews the request before the old device is revoked.',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
        if (stage == TransferStage.blocked) ...[
          const SizedBox(height: ProductSpacing.x4),
          const ProductNoticeBanner(
            title: 'Switch blocked',
            message:
                'This phone is revoked or blocked. Contact ICT before trying to activate it again.',
            tone: StatusTone.error,
          ),
        ],
        if (stage == TransferStage.complete) ...[
          const SizedBox(height: ProductSpacing.x4),
          const ProductNoticeBanner(
            title: 'This phone is active',
            message: 'This phone is already your attendance device.',
            tone: StatusTone.success,
          ),
        ],
        const SizedBox(height: ProductSpacing.x5),
        ProductCard(child: StepTimeline(steps: _steps)),
        const SizedBox(height: ProductSpacing.x5),
        FilledButton.icon(
          style: FilledButton.styleFrom(
              minimumSize: const Size(48, 56), shape: shape),
          onPressed: onScan,
          icon: const Icon(Icons.qr_code_scanner),
          label:
              const Text('Scan ICT activation QR', textAlign: TextAlign.center),
        ),
        const SizedBox(height: ProductSpacing.x3),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 56),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
            shape: shape,
          ),
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back),
          label: const Text('Back to device security',
              textAlign: TextAlign.center),
        ),
      ],
    );
  }
}

/// What the scanner screen is doing right now.
enum ScannerPhase {
  starting,
  ready,
  processing,
  success,
  permissionDenied,
  unsupported,
  cameraError,
  invalidQr,
}

const String _scanPrompt = 'Scan the short-lived QR shown by ICT.';

/// Presentation of the activation scanner. The live camera is injected as
/// [camera] so every phase can be built without a platform camera.
class ActivationScannerView extends StatelessWidget {
  const ActivationScannerView({
    super.key,
    required this.phase,
    required this.camera,
    this.message,
    this.onClose,
    this.onRetry,
  });

  final ScannerPhase phase;
  final Widget camera;

  /// Detail for [ScannerPhase.invalidQr] / [ScannerPhase.cameraError].
  final String? message;
  final VoidCallback? onClose;
  final VoidCallback? onRetry;

  bool get _blocking =>
      phase == ScannerPhase.permissionDenied ||
      phase == ScannerPhase.unsupported ||
      phase == ScannerPhase.cameraError;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ProductColors.background,
      body: Stack(
        children: [
          Positioned.fill(child: _blocking ? const SizedBox.shrink() : camera),
          if (!_blocking)
            Positioned.fill(
              child: IgnorePointer(
                child: LayoutBuilder(
                  builder: (context, c) {
                    final side =
                        (c.biggest.shortestSide * 0.55).clamp(120.0, 320.0);
                    final ok = phase == ScannerPhase.success;
                    final bad = phase == ScannerPhase.invalidQr;
                    final color = ok
                        ? ProductColors.success
                        : bad
                            ? ProductColors.error
                            : ProductColors.brandPrimary;
                    return Center(
                      child: Container(
                        width: side,
                        height: side,
                        decoration: BoxDecoration(
                          border: Border.all(color: color, width: 3),
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                                color: color.withValues(alpha: 0.45),
                                blurRadius: 28,
                                spreadRadius: -4),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Padding(
                    padding: const EdgeInsets.all(ProductSpacing.x2),
                    child: IconButton.filledTonal(
                      tooltip: 'Close',
                      constraints:
                          const BoxConstraints(minWidth: 48, minHeight: 48),
                      onPressed: onClose,
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ),
                Expanded(
                  child: _blocking
                      ? Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(ProductSpacing.x4),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 480),
                              child: _blockingView(),
                            ),
                          ),
                        )
                      : Align(
                          alignment: Alignment.bottomCenter,
                          child: _StatusPanel(phase: phase, message: message),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _blockingView() {
    return switch (phase) {
      ScannerPhase.permissionDenied => StateView(
          kind: ViewKind.error,
          icon: Icons.no_photography_outlined,
          title: 'Camera access needed',
          message:
              'Allow camera access for OfflineQR in your phone settings, then try again.',
          actionLabel: 'Try again',
          onAction: onRetry,
        ),
      ScannerPhase.unsupported => const StateView(
          kind: ViewKind.empty,
          icon: Icons.videocam_off_outlined,
          title: 'Scanning not supported',
          message:
              'This device has no usable camera. Ask ICT for another way to activate this phone.',
        ),
      _ => StateView.error(
          title: 'Camera problem',
          message: message ?? 'The camera could not start.',
          actionLabel: 'Try again',
          onAction: onRetry,
        ),
    };
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.phase, this.message});

  final ScannerPhase phase;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String text) = switch (phase) {
      ScannerPhase.starting => (
          Icons.videocam_outlined,
          ProductColors.textSecondary,
          'Starting the camera...'
        ),
      ScannerPhase.processing => (
          Icons.hourglass_top_rounded,
          ProductColors.brandPrimary,
          'Activating this phone securely...'
        ),
      ScannerPhase.success => (
          Icons.check_circle_rounded,
          ProductColors.success,
          'This phone is now your attendance device.'
        ),
      ScannerPhase.invalidQr => (
          Icons.error_outline,
          ProductColors.error,
          message ?? 'That QR code is not valid. Ask ICT to show a new one.'
        ),
      _ => (Icons.qr_code_scanner, ProductColors.brandPrimary, _scanPrompt),
    };
    final busy =
        phase == ScannerPhase.processing || phase == ScannerPhase.starting;
    return Container(
      width: double.infinity,
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.4),
      margin: const EdgeInsets.all(ProductSpacing.x3),
      padding: const EdgeInsets.all(ProductSpacing.x4),
      decoration: BoxDecoration(
        color: ProductColors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Semantics(
        liveRegion: true,
        child: SingleChildScrollView(
          child: Row(
            children: [
              if (busy)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(icon, color: color),
              const SizedBox(width: ProductSpacing.x3),
              Expanded(
                child: Text(
                  text,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: ProductColors.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceActivationScanner extends StatefulWidget {
  const _DeviceActivationScanner(
      {required this.studentId, required this.service});

  final String studentId;
  final DeviceRegistrationService service;

  @override
  State<_DeviceActivationScanner> createState() =>
      _DeviceActivationScannerState();
}

class _DeviceActivationScannerState extends State<_DeviceActivationScanner> {
  final controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool processing = false;
  bool succeeded = false;
  String? failure;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _consume(String raw) async {
    if (processing) return;
    setState(() {
      processing = true;
      failure = null;
    });
    await controller.stop();
    try {
      await widget.service.consumeReplacementActivation(
        studentId: widget.studentId,
        qrPayload: raw,
      );
      if (!mounted) return;
      setState(() => succeeded = true);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          processing = false;
          failure = error.toString();
        });
        await controller.start();
      }
    }
  }

  Future<void> _restart() async {
    try {
      await controller.start();
    } catch (_) {}
  }

  ScannerPhase _phaseFor(MobileScannerState value) {
    if (succeeded) return ScannerPhase.success;
    if (processing) return ScannerPhase.processing;
    final err = value.error;
    if (err != null) {
      return switch (err.errorCode) {
        MobileScannerErrorCode.permissionDenied =>
          ScannerPhase.permissionDenied,
        MobileScannerErrorCode.unsupported => ScannerPhase.unsupported,
        _ => ScannerPhase.cameraError,
      };
    }
    if (failure != null) return ScannerPhase.invalidQr;
    return value.isRunning ? ScannerPhase.ready : ScannerPhase.starting;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: controller,
      builder: (context, value, _) => ActivationScannerView(
        phase: _phaseFor(value),
        message: failure ?? value.error?.errorDetails?.message,
        onClose: () => Navigator.of(context).pop(false),
        onRetry: _restart,
        camera: MobileScanner(
          controller: controller,
          errorBuilder: (context, error) => const SizedBox.shrink(),
          onDetect: (capture) {
            final raw = capture.barcodes.isEmpty
                ? null
                : capture.barcodes.first.rawValue;
            if (raw != null) _consume(raw);
          },
        ),
      ),
    );
  }
}
