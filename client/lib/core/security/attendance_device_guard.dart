import '../database/local_database.dart';
import 'device_crypto.dart';

enum AttendanceDeviceGuardOutcome {
  ready,
  notRegistered,
  keyMissing,
  revoked,
  replacementPending,
  bindingConflict,
  serverCheckRequired,
}

class AttendanceDeviceGuard {
  const AttendanceDeviceGuard({
    required this.database,
    required this.keyStore,
  });

  final LocalAttendanceDatabase database;
  final DeviceKeyStore keyStore;

  Future<AttendanceDeviceGuardOutcome> check(
      {required String studentId}) async {
    final projection = database.getDeviceProjection();
    if (projection == null) {
      return AttendanceDeviceGuardOutcome.notRegistered;
    }
    if (projection.studentId != studentId) {
      return AttendanceDeviceGuardOutcome.bindingConflict;
    }
    if (projection.status == 'REVOKED') {
      return AttendanceDeviceGuardOutcome.revoked;
    }
    if (projection.status == 'PENDING') {
      return AttendanceDeviceGuardOutcome.replacementPending;
    }
    if (!await keyStore.isAvailable()) {
      return AttendanceDeviceGuardOutcome.keyMissing;
    }
    return AttendanceDeviceGuardOutcome.ready;
  }
}
