import 'dart:convert';
import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/database/local_database.dart';
import '../../core/security/secure_device_key_store.dart';
import '../../ui/kiit_components.dart';
import '../../ui/kiit_theme.dart';

class DeviceTransferPage extends StatefulWidget {
  const DeviceTransferPage({
    super.key,
    required this.database,
    required this.keyStore,
  });

  final LocalAttendanceDatabase database;
  final SecureStorageDeviceKeyStore keyStore;

  @override
  State<DeviceTransferPage> createState() => _DeviceTransferPageState();
}

class _DeviceTransferPageState extends State<DeviceTransferPage> {
  static const int _epochSeconds = 5;
  static const int _claimSeconds = 60;

  String mode = 'choice';
  String? message;
  String? transferPayload;
  bool imported = false;
  Timer? _timer;
  int _currentEpoch = _transferEpoch(DateTime.now().toUtc());
  int _secondsUntilNext = _secondsUntilNextEpoch(DateTime.now().toUtc());

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transfer Attendance Device')),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: switch (mode) {
            'primary' => _primaryDevice(),
            'new' => _newDevice(),
            _ => _choice(),
          },
        ),
      ),
    );
  }

  Widget _choice() {
    return ListView(
      key: const ValueKey('choice'),
      padding: const EdgeInsets.all(KiitSpacing.x4),
      children: [
        KiitCard(
          color: KiitColors.brandPrimarySubtle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Move attendance access to another phone',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: KiitSpacing.x3),
              Text(
                'Keep your registered phone nearby. The primary phone creates a one-time transfer QR; the new phone scans it inside this app.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(height: KiitSpacing.x4),
        _ModeCard(
          icon: Icons.phone_android,
          title: 'Primary Device',
          subtitle: 'This is the already registered phone. Show transfer QR.',
          onTap: () {
            setState(() => mode = 'primary');
            _startDynamicTransferQr();
            _buildTransferPayload();
          },
        ),
        _ModeCard(
          icon: Icons.qr_code_scanner,
          title: 'New Device',
          subtitle:
              'This phone will scan the primary device QR and import access.',
          onTap: () => setState(() => mode = 'new'),
        ),
      ],
    );
  }

  Widget _primaryDevice() {
    final student = widget.database.getCurrentStudent();
    final device = widget.database.getDeviceProjection();
    final canTransfer = student != null && device?.status == 'ACTIVE';
    return ListView(
      key: const ValueKey('primary'),
      padding: const EdgeInsets.all(KiitSpacing.x4),
      children: [
        KiitCard(
          color: KiitColors.brandPrimarySubtle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Primary Device',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: KiitSpacing.x2),
              Text(
                'Show this QR only to your new phone. It transfers the registered attendance credential for the same student account.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: KiitSpacing.x5),
              if (!canTransfer)
                _TransferNotice(
                  icon: Icons.verified_user_outlined,
                  title: 'Register this phone first',
                  body:
                      'This screen only works from the current registered phone. Go back, register this device, then open Primary Device again.',
                  tone: StatusTone.warning,
                  action: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back to registration'),
                  ),
                )
              else if (transferPayload == null)
                const _TransferNotice(
                  icon: Icons.sync,
                  title: 'Preparing QR',
                  body: 'Creating a short-lived transfer QR from this phone.',
                  tone: StatusTone.info,
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final size = math.min(constraints.maxWidth - 24, 320.0);
                    return Center(
                      child: Container(
                        padding: const EdgeInsets.all(KiitSpacing.x4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: KiitColors.brandPrimary,
                            width: 2,
                          ),
                        ),
                        child: QrImageView(
                          data: transferPayload!,
                          version: QrVersions.auto,
                          size: size,
                          backgroundColor: Colors.white,
                          errorCorrectionLevel: QrErrorCorrectLevel.M,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: Colors.black,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: KiitSpacing.x4),
              const _TransferNotice(
                icon: Icons.timer_outlined,
                title: 'Dynamic transfer QR',
                body:
                    'QR changes every 5 seconds. A scanned transfer can complete for 60 seconds.',
                tone: StatusTone.info,
              ),
              const SizedBox(height: KiitSpacing.x3),
              Text(
                'Refreshes in ${_secondsUntilNext.toString().padLeft(2, '0')}s',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: KiitColors.brandPrimaryStrong,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: KiitSpacing.x4),
              OutlinedButton.icon(
                onPressed:
                    transferPayload == null ? null : _finishPrimaryTransfer,
                icon: const Icon(Icons.lock_reset),
                label: const Text('Finish Transfer on This Phone'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _newDevice() {
    return Scaffold(
      key: const ValueKey('new'),
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(
              fit: BoxFit.cover,
              onDetect: (capture) {
                if (imported) return;
                final code = capture.barcodes.isEmpty
                    ? null
                    : capture.barcodes.first.rawValue;
                if (code != null) {
                  _importPayload(code);
                }
              },
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Container(color: Colors.black.withValues(alpha: 0.18)),
            ),
          ),
          const Positioned.fill(child: _ScannerFrame()),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                onPressed: () => setState(() => mode = 'choice'),
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.all(KiitSpacing.x4),
                padding: const EdgeInsets.all(KiitSpacing.x4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      imported
                          ? Icons.verified_user_outlined
                          : Icons.qr_code_scanner,
                      color: KiitColors.brandPrimaryStrong,
                      size: 32,
                    ),
                    const SizedBox(height: KiitSpacing.x2),
                    Text(
                      imported
                          ? 'Device transfer complete'
                          : 'Scan the primary device QR',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: KiitSpacing.x2),
                    Text(
                      imported
                          ? 'Verify this phone once online before attendance.'
                          : 'Point this phone at the transfer QR shown on your primary device.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (message != null) ...[
                      const SizedBox(height: KiitSpacing.x3),
                      Text(
                        message!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color:
                              imported ? KiitColors.success : KiitColors.error,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _buildTransferPayload() async {
    final epoch = _currentEpoch;
    final student = widget.database.getCurrentStudent();
    final device = widget.database.getDeviceProjection();
    if (student == null || device == null || device.status != 'ACTIVE') {
      setState(
          () => message = 'Register and verify this device before transfer.');
      return;
    }
    final seed = await widget.keyStore.exportSeed();
    final signer = await widget.keyStore.loadSigner();
    if (seed == null) {
      setState(() => message = 'Local attendance key is missing.');
      return;
    }
    if (signer == null) {
      setState(() => message = 'Local attendance signer is missing.');
      return;
    }
    final issuedAt = DateTime.now().toUtc();
    final expiresAt = issuedAt.add(const Duration(seconds: _claimSeconds));
    final nonce =
        '${issuedAt.microsecondsSinceEpoch}-${math.Random.secure().nextInt(1 << 32)}';
    final canonical = _canonicalTransfer(
      studentId: student.id,
      deviceRegistrationId: device.deviceRegistrationId,
      keyFingerprint: device.keyFingerprint,
      epoch: epoch,
      issuedAt: issuedAt.toIso8601String(),
      expiresAt: expiresAt.toIso8601String(),
      nonce: nonce,
    );
    final signature = await signer.sign(canonical);
    if (!mounted || epoch != _currentEpoch) {
      return;
    }
    setState(() {
      message = null;
      transferPayload = jsonEncode({
        'p': 'KIIT_DEVICE_TRANSFER_V1',
        'e': epoch,
        'iat': issuedAt.toIso8601String(),
        'exp': expiresAt.toIso8601String(),
        'n': nonce,
        'sid': student.id,
        'roll': student.rollNumber,
        'sec': student.sectionCode,
        'did': device.deviceRegistrationId,
        'st': device.status,
        'fp': device.keyFingerprint,
        'plat': device.platform,
        'label': device.displayLabel,
        'v': device.serverVersion,
        'k': seed,
        'sig': signature,
      });
    });
  }

  Future<void> _importPayload(String raw) async {
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      if (decoded['p'] != 'KIIT_DEVICE_TRANSFER_V1') {
        throw StateError('This is not a KIIT device transfer QR.');
      }
      final expiresAt = DateTime.parse(decoded['exp'] as String);
      if (DateTime.now().toUtc().isAfter(expiresAt)) {
        throw StateError('Transfer QR has expired.');
      }
      final student = widget.database.getCurrentStudent();
      if (student == null || decoded['sid'] != student.id) {
        throw StateError('Transfer QR belongs to another student.');
      }
      await widget.keyStore.importSeed(decoded['k'] as String);
      final signer = await widget.keyStore.loadSigner();
      final verified = await signer?.verify(
            _canonicalTransfer(
              studentId: decoded['sid'] as String,
              deviceRegistrationId: decoded['did'] as String,
              keyFingerprint: decoded['fp'] as String,
              epoch: decoded['e'] as int,
              issuedAt: decoded['iat'] as String,
              expiresAt: decoded['exp'] as String,
              nonce: decoded['n'] as String,
            ),
            decoded['sig'] as String,
          ) ??
          false;
      if (!verified) {
        await widget.keyStore.deleteSeed();
        throw StateError('Transfer QR signature could not be verified.');
      }
      widget.database.saveDeviceProjection(
        DeviceRegistrationProjection(
          deviceRegistrationId: decoded['did'] as String,
          studentId: decoded['sid'] as String,
          status: decoded['st'] as String,
          keyFingerprint: decoded['fp'] as String,
          platform: decoded['plat'] as String,
          displayLabel: decoded['label'] as String?,
          lastVerifiedAt: null,
          serverVersion: decoded['v'] as int? ?? 1,
        ),
      );
      setState(() {
        imported = true;
        message = 'Attendance device transferred. Verify once online.';
      });
    } catch (error) {
      setState(
          () => message = error.toString().replaceFirst('Bad state: ', ''));
    }
  }

  Future<void> _finishPrimaryTransfer() async {
    await widget.keyStore.deleteSeed();
    widget.database.clearDeviceProjection();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Attendance device moved from this phone.')),
    );
    Navigator.of(context).pop();
  }

  void _startDynamicTransferQr() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now().toUtc();
      final epoch = _transferEpoch(now);
      final seconds = _secondsUntilNextEpoch(now);
      if (!mounted || mode != 'primary') {
        return;
      }
      setState(() => _secondsUntilNext = seconds);
      if (epoch != _currentEpoch) {
        setState(() {
          _currentEpoch = epoch;
          transferPayload = null;
        });
        _buildTransferPayload();
      }
    });
  }

  static int _transferEpoch(DateTime now) =>
      now.millisecondsSinceEpoch ~/ (_epochSeconds * 1000);

  static int _secondsUntilNextEpoch(DateTime now) {
    final elapsed = (now.millisecondsSinceEpoch ~/ 1000) % _epochSeconds;
    return _epochSeconds - elapsed;
  }

  String _canonicalTransfer({
    required String studentId,
    required String deviceRegistrationId,
    required String keyFingerprint,
    required int epoch,
    required String issuedAt,
    required String expiresAt,
    required String nonce,
  }) =>
      [
        'KIIT_DEVICE_TRANSFER_V1',
        'student_id:$studentId',
        'device_registration_id:$deviceRegistrationId',
        'key_fingerprint:$keyFingerprint',
        'epoch:$epoch',
        'issued_at:$issuedAt',
        'expires_at:$expiresAt',
        'nonce:$nonce',
      ].join('\n');
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KiitSpacing.x3),
      child: KiitCard(
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: KiitColors.brandPrimaryStrong),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _TransferNotice extends StatelessWidget {
  const _TransferNotice({
    required this.icon,
    required this.title,
    required this.body,
    required this.tone,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final StatusTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      StatusTone.success => KiitColors.success,
      StatusTone.warning => KiitColors.warning,
      StatusTone.error => KiitColors.error,
      StatusTone.info => KiitColors.info,
      StatusTone.neutral => KiitColors.textSecondary,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(KiitSpacing.x4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: KiitSpacing.x2),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: KiitSpacing.x2),
          Text(body, style: Theme.of(context).textTheme.bodyMedium),
          if (action != null) ...[
            const SizedBox(height: KiitSpacing.x3),
            action!,
          ],
        ],
      ),
    );
  }
}

class _ScannerFrame extends StatelessWidget {
  const _ScannerFrame();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(constraints.maxWidth * 0.78, 360.0);
        final height = math.min(constraints.maxHeight * 0.48, 360.0);
        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: CustomPaint(
              painter: _ScannerFramePainter(),
            ),
          ),
        );
      },
    );
  }
}

class _ScannerFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final cornerPaint = Paint()
      ..color = KiitColors.brandPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(28),
    );
    canvas.drawRRect(rect, borderPaint);

    const length = 72.0;
    const radius = 28.0;
    final path = Path()
      ..moveTo(radius, 0)
      ..lineTo(length, 0)
      ..moveTo(0, radius)
      ..lineTo(0, length)
      ..moveTo(size.width - length, 0)
      ..lineTo(size.width - radius, 0)
      ..moveTo(size.width, radius)
      ..lineTo(size.width, length)
      ..moveTo(0, size.height - length)
      ..lineTo(0, size.height - radius)
      ..moveTo(radius, size.height)
      ..lineTo(length, size.height)
      ..moveTo(size.width - length, size.height)
      ..lineTo(size.width - radius, size.height)
      ..moveTo(size.width, size.height - length)
      ..lineTo(size.width, size.height - radius);
    canvas.drawPath(path, cornerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
