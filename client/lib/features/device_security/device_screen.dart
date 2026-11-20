import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/database/local_database.dart';
import '../../core/network/api_config.dart';
import '../../core/security/attendance_device_guard.dart';
import '../../core/security/device_registration_service.dart';
import '../../core/security/device_profile.dart';
import '../../core/security/secure_device_key_store.dart';
import '../../core/security/student_auth_store.dart';
import '../../ui/dark_kit.dart';
import '../../ui/dark_kit_extra_b.dart';
import '../../ui/product_components.dart';
import '../../ui/product_theme.dart';
import '../../ui/responsive.dart';
import '../../ui/state_views.dart';
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
  String? failure;
  bool loaded = false;
  bool busy = false;
  String? activity;
  VoidCallback? _lastAction;
  final DeviceProfileCollector _profileCollector =
      const DeviceProfileCollector();

  @override
  void initState() {
    super.initState();
    keyStore = SecureStorageDeviceKeyStore();
    service = DeviceRegistrationService(
      database: widget.database,
      keyStore: keyStore,
      baseUri: apiBaseUri(),
      authStore: StudentAuthStore(),
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
    if (!mounted) return;
    setState(() {
      projection = widget.database.getDeviceProjection();
      guardOutcome = outcome;
      loaded = true;
    });
  }

  Future<void> _register() async {
    final student = widget.database.getCurrentStudent();
    if (student == null) {
      setState(
          () => message = 'Sync academic data before registering a device.');
      return;
    }
    await _run('Registering this phone', _register, () async {
      await service.enroll(
        studentId: student.id,
        platform: Platform.isAndroid ? 'Android' : Platform.operatingSystem,
        displayLabel:
            Platform.isAndroid ? 'Android Device' : 'Development Device',
        deviceProfile: await _profileCollector.collect(),
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
    await _run('Verifying this phone', _verify, () async {
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
    await _run('Sending replacement request', _relinkDevice, () async {
      final current = await service.currentDevice(studentId: student.id);
      if (current == null) {
        await service.enroll(
          studentId: student.id,
          platform: Platform.isAndroid ? 'Android' : Platform.operatingSystem,
          displayLabel:
              Platform.isAndroid ? 'Android Device' : 'Development Device',
          deviceProfile: await _profileCollector.collect(),
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
        deviceProfile: await _profileCollector.collect(),
      );
      message =
          'Replacement request sent to ICT. This phone remains blocked until approved.';
    });
  }

  Future<void> _run(
    String label,
    VoidCallback retry,
    Future<void> Function() action,
  ) async {
    setState(() {
      busy = true;
      activity = label;
      message = null;
      failure = null;
      _lastAction = retry;
    });
    try {
      await action();
    } catch (error) {
      failure = error.toString();
    } finally {
      await _refresh();
      if (mounted) {
        setState(() {
          busy = false;
          activity = null;
        });
      }
    }
  }

  DeviceViewKind get _kind {
    if (!loaded) return DeviceViewKind.loading;
    if (failure != null) {
      return DeviceViewStatus.looksOffline(failure!)
          ? DeviceViewKind.offline
          : DeviceViewKind.verificationFailed;
    }
    return switch (guardOutcome) {
      AttendanceDeviceGuardOutcome.ready => DeviceViewKind.active,
      AttendanceDeviceGuardOutcome.keyMissing ||
      AttendanceDeviceGuardOutcome.serverCheckRequired =>
        DeviceViewKind.pendingVerification,
      AttendanceDeviceGuardOutcome.revoked => DeviceViewKind.revoked,
      AttendanceDeviceGuardOutcome.bindingConflict => DeviceViewKind.blocked,
      AttendanceDeviceGuardOutcome.replacementPending =>
        DeviceViewKind.relinkInProgress,
      AttendanceDeviceGuardOutcome.notRegistered ||
      null =>
        DeviceViewKind.notRegistered,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance Device')),
      body: SafeArea(
        child: DeviceStatusView(
          kind: _kind,
          projection: projection,
          notice: message,
          error: failure,
          busy: busy,
          activity: activity,
          onRegister: _register,
          onVerify: _verify,
          onRelink: _relinkDevice,
          onRetry: () {
            final retry = _lastAction;
            if (retry == null) {
              setState(() => failure = null);
              _refresh();
            } else {
              retry();
            }
          },
          onTransfer: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DeviceTransferPage(
                  database: widget.database,
                  keyStore: keyStore,
                  service: service,
                ),
              ),
            );
            await _refresh();
          },
        ),
      ),
    );
  }
}

/// Every distinct situation the device screen can be in.
enum DeviceViewKind {
  loading,
  notRegistered,
  pendingVerification,
  active,
  revoked,
  blocked,
  verificationFailed,
  offline,
  relinkInProgress,
}

class DeviceViewStatus {
  const DeviceViewStatus._();

  /// Best-effort: does this error text describe a connectivity problem?
  static bool looksOffline(String message) {
    final m = message.toLowerCase();
    return m.contains('socket') ||
        m.contains('connection') ||
        m.contains('network') ||
        m.contains('timeout') ||
        m.contains('timed out') ||
        m.contains('unreachable') ||
        m.contains('offline');
  }

  static String title(DeviceViewKind kind) => switch (kind) {
        DeviceViewKind.loading => 'Checking',
        DeviceViewKind.notRegistered => 'Not Registered',
        DeviceViewKind.pendingVerification => 'Verification Needed',
        DeviceViewKind.active => 'Registered',
        DeviceViewKind.revoked => 'Revoked',
        DeviceViewKind.blocked => 'Check Required',
        DeviceViewKind.verificationFailed => 'Verification Failed',
        DeviceViewKind.offline => 'Offline',
        DeviceViewKind.relinkInProgress => 'Replacement Pending',
      };

  static String description(DeviceViewKind kind) => switch (kind) {
        DeviceViewKind.loading => 'Checking this phone registration.',
        DeviceViewKind.notRegistered =>
          'No attendance device registered locally.',
        DeviceViewKind.pendingVerification =>
          'This phone needs to be verified with the server before it can submit attendance.',
        DeviceViewKind.active =>
          'This phone is ready to submit attendance securely.',
        DeviceViewKind.revoked => 'Device registration is revoked.',
        DeviceViewKind.blocked =>
          'This phone appears to be linked to another student.',
        DeviceViewKind.verificationFailed =>
          'The last request did not complete.',
        DeviceViewKind.offline =>
          'The server could not be reached. Your saved data is safe.',
        DeviceViewKind.relinkInProgress =>
          'Device replacement is pending approval.',
      };

  static IconData icon(DeviceViewKind kind) => switch (kind) {
        DeviceViewKind.active => Icons.verified_user_outlined,
        DeviceViewKind.notRegistered ||
        DeviceViewKind.loading =>
          Icons.info_outline,
        DeviceViewKind.offline => Icons.cloud_off_outlined,
        DeviceViewKind.relinkInProgress => Icons.hourglass_top_rounded,
        DeviceViewKind.revoked || DeviceViewKind.blocked => Icons.block_rounded,
        _ => Icons.error_outline,
      };

  static StatusTone tone(DeviceViewKind kind) => switch (kind) {
        DeviceViewKind.active => StatusTone.success,
        DeviceViewKind.notRegistered ||
        DeviceViewKind.loading =>
          StatusTone.info,
        DeviceViewKind.revoked ||
        DeviceViewKind.blocked ||
        DeviceViewKind.verificationFailed =>
          StatusTone.error,
        _ => StatusTone.warning,
      };

  static Color color(DeviceViewKind kind) => switch (tone(kind)) {
        StatusTone.success => ProductColors.success,
        StatusTone.warning => ProductColors.warning,
        StatusTone.error => ProductColors.error,
        _ => ProductColors.info,
      };
}

/// Pure presentation of the device screen body: no services, no storage.
/// [DeviceScreen] feeds it; tests feed it every [DeviceViewKind].
class DeviceStatusView extends StatelessWidget {
  const DeviceStatusView({
    super.key,
    required this.kind,
    this.projection,
    this.notice,
    this.error,
    this.busy = false,
    this.activity,
    this.onRegister,
    this.onVerify,
    this.onRelink,
    this.onTransfer,
    this.onRetry,
  });

  final DeviceViewKind kind;
  final DeviceRegistrationProjection? projection;
  final String? notice;
  final String? error;
  final bool busy;

  /// Short label of the request in flight, e.g. "Verifying this phone".
  final String? activity;
  final VoidCallback? onRegister;
  final VoidCallback? onVerify;
  final VoidCallback? onRelink;
  final VoidCallback? onTransfer;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = projection;
    final loading = kind == DeviceViewKind.loading;
    final heroColor = DeviceViewStatus.color(kind);
    final locked = busy || loading;
    final outline = BorderSide(color: Colors.white.withValues(alpha: 0.14));
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(20));
    return AdaptivePage(
      children: [
        const SizedBox(height: ProductSpacing.x4),
        if (loading)
          const StateView.loading(compact: true)
        else
          FadeSlideIn(
            child: GlassCard(
              radius: 28,
              glow: heroColor,
              padding: const EdgeInsets.all(ProductSpacing.x5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      GlowMark(
                        size: 56,
                        child: IconChip(
                            icon: DeviceViewStatus.icon(kind),
                            size: 56,
                            color: heroColor),
                      ),
                      const SizedBox(width: ProductSpacing.x4),
                      Expanded(
                        child: Text('This phone',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.headlineSmall
                                ?.copyWith(letterSpacing: -0.6)),
                      ),
                    ],
                  ),
                  const SizedBox(height: ProductSpacing.x4),
                  StatusChip(
                    label: DeviceViewStatus.title(kind),
                    icon: DeviceViewStatus.icon(kind),
                    tone: DeviceViewStatus.tone(kind),
                  ),
                  const SizedBox(height: ProductSpacing.x3),
                  Text(DeviceViewStatus.description(kind),
                      style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ),
        if (activity != null) ...[
          const SizedBox(height: ProductSpacing.x4),
          _BusyStrip(label: activity!),
        ],
        if (kind == DeviceViewKind.verificationFailed) ...[
          const SizedBox(height: ProductSpacing.x4),
          StateView.error(
            title: 'Verification failed',
            message: error ?? 'The request did not complete.',
            actionLabel: 'Try again',
            onAction: busy ? null : onRetry,
            compact: true,
          ),
        ],
        if (kind == DeviceViewKind.offline) ...[
          const SizedBox(height: ProductSpacing.x4),
          StateView.offline(
            title: 'You are offline',
            message:
                'Connect to the internet and try again. Your saved data is safe on this phone.',
            actionLabel: 'Try again',
            onAction: busy ? null : onRetry,
            compact: true,
          ),
        ],
        if (kind == DeviceViewKind.revoked ||
            kind == DeviceViewKind.blocked) ...[
          const SizedBox(height: ProductSpacing.x4),
          ProductNoticeBanner(
            title: kind == DeviceViewKind.revoked
                ? 'This phone cannot submit attendance'
                : 'Blocked until reviewed',
            message: kind == DeviceViewKind.revoked
                ? 'Ask ICT to approve a replacement, or use Relink below if this is your new phone.'
                : 'Contact ICT to resolve the link between this phone and your account.',
            tone: StatusTone.error,
          ),
        ],
        if (kind == DeviceViewKind.relinkInProgress) ...[
          const SizedBox(height: ProductSpacing.x4),
          const ProductNoticeBanner(
            title: 'Waiting for ICT',
            message:
                'This phone remains blocked until the replacement is approved. Scan the activation QR from ICT in Transfer device.',
            tone: StatusTone.warning,
          ),
        ],
        if (notice != null) ...[
          const SizedBox(height: ProductSpacing.x4),
          ProductNoticeBanner(title: 'Update', message: notice!),
        ],
        if (current != null) ...[
          const SizedBox(height: ProductSpacing.x4),
          ProductCard(
            child: Column(
              children: [
                _InfoRow(label: 'Device', value: current.platform),
                const Divider(),
                _InfoRow(
                  label: 'Registration',
                  value: current.status == 'ACTIVE'
                      ? 'Registered'
                      : current.status,
                ),
                const Divider(),
                _InfoRow(
                  label: 'Last verified',
                  value: current.lastVerifiedAt ?? 'Not verified yet',
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: ProductSpacing.x5),
        FilledButton(
          style: FilledButton.styleFrom(
              minimumSize: const Size(48, 56), shape: shape),
          onPressed: locked || current != null ? null : onRegister,
          child: Text(busy ? 'Working' : 'Register this device',
              textAlign: TextAlign.center),
        ),
        const SizedBox(height: ProductSpacing.x2),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 56), side: outline, shape: shape),
          onPressed: locked || current == null ? null : onVerify,
          child: const Text('Verify device', textAlign: TextAlign.center),
        ),
        const SizedBox(height: ProductSpacing.x6),
        Text('Changing phones',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4)),
        const SizedBox(height: ProductSpacing.x1),
        Text('Use these only when you are replacing or recovering a phone.',
            style: theme.textTheme.bodyMedium),
        const SizedBox(height: ProductSpacing.x3),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 56), side: outline, shape: shape),
          onPressed: locked ? null : onTransfer,
          icon: const Icon(Icons.sync_alt),
          label: const Text('Transfer device', textAlign: TextAlign.center),
        ),
        const SizedBox(height: ProductSpacing.x2),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 56),
            shape: shape,
            foregroundColor: ProductColors.error,
            side: BorderSide(color: ProductColors.error.withValues(alpha: 0.4)),
          ),
          onPressed: locked ? null : onRelink,
          icon: const Icon(Icons.admin_panel_settings_outlined),
          label: const Text('Relink lost or reinstalled phone',
              textAlign: TextAlign.center),
        ),
      ],
    );
  }
}

class _BusyStrip extends StatelessWidget {
  const _BusyStrip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ProductColors.info.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(ProductRadius.medium),
          border: Border.all(color: ProductColors.info.withValues(alpha: 0.3)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: ProductSpacing.x3, vertical: ProductSpacing.x3),
          child: Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: ProductSpacing.x3),
              Expanded(
                child: Text('$label...',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: ProductColors.textPrimary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ProductSpacing.x2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: t.bodyMedium),
          ),
          const SizedBox(width: ProductSpacing.x3),
          Expanded(
            flex: 3,
            child: Text(
              value,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: t.labelLarge,
            ),
          ),
        ],
      ),
    );
  }
}
