import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/database/local_database.dart';
import '../../core/network/api_config.dart';
import '../../core/security/attendance_device_guard.dart';
import '../../core/security/device_registration_service.dart';
import '../../core/security/secure_device_key_store.dart';
import '../../ui/kiit_components.dart';
import '../../ui/kiit_theme.dart';
import 'device_transfer_page.dart';

class DeviceScreen extends StatefulWidget {
  const DeviceScreen({super.key, required this.database});

  final LocalAttendanceDatabase database;

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  late final SecureStorageDeviceKeyStore keyStore;
  late final DeviceRegistrationService service;
  DeviceRegistrationProjection? projection;
  AttendanceDeviceGuardOutcome? guardOutcome;
  String? message;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    keyStore = SecureStorageDeviceKeyStore();
    service = DeviceRegistrationService(
      database: widget.database,
      keyStore: keyStore,
      baseUri: apiBaseUri(),
    );
    _refresh();
  }

  Future<void> _refresh() async {
    final student = widget.database.getCurrentStudent();
    final outcome = student == null
        ? AttendanceDeviceGuardOutcome.notRegistered
        : await AttendanceDeviceGuard(
            database: widget.database,
            keyStore: keyStore,
          ).check(studentId: student.id);
    setState(() {
      projection = widget.database.getDeviceProjection();
      guardOutcome = outcome;
    });
  }

  Future<void> _register() async {
    final student = widget.database.getCurrentStudent();
    if (student == null) {
      setState(
          () => message = 'Sync academic data before registering a device.');
      return;
    }
    await _run(() async {
      await service.enroll(
        studentId: student.id,
        platform: Platform.isAndroid ? 'Android' : Platform.operatingSystem,
        displayLabel:
            Platform.isAndroid ? 'Android Device' : 'Development Device',
      );
      message = 'Device registered.';
    });
  }

  Future<void> _verify() async {
    final student = widget.database.getCurrentStudent();
    final current = projection;
    if (student == null || current == null) {
      return;
    }
    await _run(() async {
      await service.verify(
        studentId: student.id,
        deviceRegistrationId: current.deviceRegistrationId,
      );
      message = 'Device verified.';
    });
  }

  Future<void> _relinkDevice() async {
    final student = widget.database.getCurrentStudent();
    if (student == null) {
      setState(() => message = 'Sync academic data before relinking a device.');
      return;
    }
    await _run(() async {
      final current = await service.currentDevice(studentId: student.id);
      if (current == null) {
        await service.enroll(
          studentId: student.id,
          platform: Platform.isAndroid ? 'Android' : Platform.operatingSystem,
          displayLabel:
              Platform.isAndroid ? 'Android Device' : 'Development Device',
        );
        message = 'Device registered for this account.';
        return;
      }
      await service.requestReplacement(
        studentId: student.id,
        platform: Platform.isAndroid ? 'Android' : Platform.operatingSystem,
        reason: 'Primary phone unavailable, lost, or app reinstalled',
        displayLabel:
            Platform.isAndroid ? 'Android Device' : 'Development Device',
      );
      message = 'Device relinked after replacement approval.';
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action();
    } catch (error) {
      message = error.toString();
    } finally {
      await _refresh();
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = projection;
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance Device')),
      body: ListView(
        padding: const EdgeInsets.all(KiitSpacing.x4),
        children: [
          KiitCard(
            color: KiitColors.brandPrimarySubtle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('This Phone',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: KiitSpacing.x3),
                StatusChip(
                  label: _statusTitle(guardOutcome),
                  icon: _statusIcon(guardOutcome),
                  tone: _statusTone(guardOutcome),
                ),
                const SizedBox(height: KiitSpacing.x4),
                Text(
                  _labelFor(guardOutcome),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: KiitSpacing.x5),
          if (current != null) ...[
            KiitCard(
              child: Column(
                children: [
                  _InfoRow(label: 'Device', value: current.platform),
                  _InfoRow(
                    label: 'Registration',
                    value: current.status == 'ACTIVE'
                        ? 'Registered'
                        : current.status,
                  ),
                  _InfoRow(
                    label: 'Last Verified',
                    value: current.lastVerifiedAt ?? 'Not verified yet',
                  ),
                ],
              ),
            ),
            const SizedBox(height: KiitSpacing.x5),
          ],
          FilledButton(
            onPressed: busy || current != null ? null : _register,
            child: Text(busy ? 'Working' : 'Register This Device'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: busy || current == null ? null : _verify,
            child: const Text('Verify Device'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: busy
                ? null
                : () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DeviceTransferPage(
                          database: widget.database,
                          keyStore: keyStore,
                        ),
                      ),
                    );
                    await _refresh();
                  },
            icon: const Icon(Icons.sync_alt),
            label: const Text('Transfer Device'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: busy ? null : _relinkDevice,
            icon: const Icon(Icons.admin_panel_settings_outlined),
            label: const Text('Relink Lost or Reinstalled Phone'),
          ),
          if (message != null) ...[
            const SizedBox(height: 24),
            Text(message!),
          ],
        ],
      ),
    );
  }

  String _labelFor(AttendanceDeviceGuardOutcome? outcome) {
    return switch (outcome) {
      AttendanceDeviceGuardOutcome.ready =>
        'This phone is ready to submit attendance securely.',
      AttendanceDeviceGuardOutcome.keyMissing =>
        'The attendance credential is unavailable. Transfer from the primary device or contact administration.',
      AttendanceDeviceGuardOutcome.revoked => 'Device registration is revoked.',
      AttendanceDeviceGuardOutcome.replacementPending =>
        'Device replacement is pending approval.',
      AttendanceDeviceGuardOutcome.bindingConflict =>
        'This phone appears to be linked to another student.',
      AttendanceDeviceGuardOutcome.serverCheckRequired =>
        'Server verification is required.',
      AttendanceDeviceGuardOutcome.notRegistered ||
      null =>
        'No attendance device registered locally.',
    };
  }

  String _statusTitle(AttendanceDeviceGuardOutcome? outcome) {
    return switch (outcome) {
      AttendanceDeviceGuardOutcome.ready => 'Registered',
      AttendanceDeviceGuardOutcome.keyMissing => 'Verification Needed',
      AttendanceDeviceGuardOutcome.revoked => 'Revoked',
      AttendanceDeviceGuardOutcome.replacementPending => 'Replacement Pending',
      AttendanceDeviceGuardOutcome.bindingConflict => 'Check Required',
      AttendanceDeviceGuardOutcome.serverCheckRequired => 'Verify Device',
      AttendanceDeviceGuardOutcome.notRegistered || null => 'Not Registered',
    };
  }

  IconData _statusIcon(AttendanceDeviceGuardOutcome? outcome) {
    return switch (outcome) {
      AttendanceDeviceGuardOutcome.ready => Icons.verified_user_outlined,
      AttendanceDeviceGuardOutcome.notRegistered || null => Icons.info_outline,
      _ => Icons.error_outline,
    };
  }

  StatusTone _statusTone(AttendanceDeviceGuardOutcome? outcome) {
    return switch (outcome) {
      AttendanceDeviceGuardOutcome.ready => StatusTone.success,
      AttendanceDeviceGuardOutcome.notRegistered || null => StatusTone.info,
      _ => StatusTone.warning,
    };
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: KiitSpacing.x2),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ],
      ),
    );
  }
}
