import 'package:flutter/material.dart';

import '../../core/database/local_database.dart';
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
  });

  final LocalAttendanceDatabase database;
  final SecureStorageDeviceKeyStore keyStore;

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
            body: 'Sign in with the same KIIT account and choose Relink Lost or Reinstalled Phone.',
          ),
          const _Step(
            number: '2',
            title: 'Create a replacement request',
            body: 'The new device creates a fresh protected key and submits its make, model, OS, and physical-device signal for review.',
          ),
          const _Step(
            number: '3',
            title: 'Wait for ICT approval',
            body: 'ICT checks the device history and approves or rejects the switch. Only approval activates the new phone.',
          ),
          const SizedBox(height: KiitSpacing.x5),
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
