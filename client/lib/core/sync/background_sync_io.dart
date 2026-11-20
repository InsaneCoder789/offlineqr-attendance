import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../database/local_database.dart';
import '../network/api_config.dart';
import 'attendance_proof_sync_service.dart';

const _syncTask = 'attendance-proof-sync';
const _periodicSyncName =
    'com.offlineqr.attendance.sync.periodic';

@pragma('vm:entry-point')
void attendanceSyncDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    final database = await LocalAttendanceDatabase.openDefault();
    try {
      final report = await AttendanceProofSyncService(
        database: database,
        baseUri: apiBaseUri(),
      ).syncPendingProofs(force: true);
      return report.retryPending == 0;
    } catch (_) {
      return false;
    } finally {
      database.close();
    }
  });
}

Future<void> initializeBackgroundAttendanceSync() async {
  await Workmanager().initialize(attendanceSyncDispatcher);
  await Workmanager().registerPeriodicTask(
    _periodicSyncName,
    _syncTask,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(
      networkType: NetworkType.connected,
      requiresStorageNotLow: true,
    ),
  );
}

Future<void> scheduleImmediateAttendanceSync() async {
  await Workmanager().registerOneOffTask(
    'attendance-proof-${DateTime.now().millisecondsSinceEpoch}',
    _syncTask,
    constraints: Constraints(networkType: NetworkType.connected),
  );
}
