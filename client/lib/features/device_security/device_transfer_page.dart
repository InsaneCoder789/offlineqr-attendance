import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/database/local_database.dart';
import '../../core/security/device_registration_service.dart';
import '../../core/security/secure_device_key_store.dart';
import '../../ui/kiit_components.dart';
import '../../ui/kiit_theme.dart';

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
      body: ListView(
        padding: const EdgeInsets.all(KiitSpacing.x4),
        children: [
          KiitCard(
            color: KiitColors.brandPrimarySubtle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.admin_panel_settings_outlined,
                    color: KiitColors.brandPrimaryStrong, size: 34),
                const SizedBox(height: KiitSpacing.x3),
                Text('ICT-approved device switch',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: KiitSpacing.x2),
                Text(
                  'Attendance credentials are bound to this phone and are never copied through a QR code. A new phone creates its own key, then ICT reviews the request before the old device is revoked.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: KiitSpacing.x5),
          const _Step(
            number: '1',
            title: 'Open KIIT Attendance on the new phone',
            body:
                'Sign in with the same KIIT account and choose Relink Lost or Reinstalled Phone.',
          ),
          const _Step(
            number: '2',
            title: 'Create a replacement request',
            body:
                'The new device creates a fresh protected key and submits its make, model, OS, and physical-device signal for review.',
          ),
          const _Step(
            number: '3',
            title: 'Wait for ICT approval',
            body:
                'ICT checks the device history, approves the request, then displays a five-minute activation QR. Scan it on this new phone to complete the switch.',
          ),
          const SizedBox(height: KiitSpacing.x5),
          FilledButton.icon(
            onPressed: () async {
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
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan ICT Activation QR'),
          ),
          const SizedBox(height: KiitSpacing.x3),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back to Device Security'),
          ),
        ],
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
  String message = 'Scan the short-lived QR shown by ICT.';

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _consume(String raw) async {
    if (processing) return;
    setState(() => processing = true);
    await controller.stop();
    try {
      await widget.service.consumeReplacementActivation(
        studentId: widget.studentId,
        qrPayload: raw,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          processing = false;
          message = error.toString();
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
          children: [
            MobileScanner(
              controller: controller,
              onDetect: (capture) {
                final raw = capture.barcodes.isEmpty
                    ? null
                    : capture.barcodes.first.rawValue;
                if (raw != null) _consume(raw);
              },
            ),
            Positioned(
              top: KiitSpacing.x3,
              left: KiitSpacing.x3,
              child: IconButton.filledTonal(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(false),
                icon: const Icon(Icons.close),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(KiitSpacing.x5),
                color: Colors.black87,
                child: Text(
                  processing ? 'Activating this phone securely...' : message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.title, required this.body});

  final String number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KiitSpacing.x4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: KiitColors.brandPrimarySoft,
            child: Text(number,
                style: const TextStyle(
                    color: KiitColors.brandPrimaryStrong,
                    fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: KiitSpacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(body, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
