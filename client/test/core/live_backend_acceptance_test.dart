import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:client/core/database/local_database.dart';
import 'package:client/core/sync/bootstrap_sync_service.dart';

void main() {
  test('Goal 02 live backend sync/offline acceptance step', () async {
    final dbPath = Platform.environment['GOAL02_DB_PATH'];
    final mode = Platform.environment['GOAL02_MODE'];
    final backendUrl = Platform.environment['GOAL02_BACKEND_URL'];

    if (dbPath == null || mode == null) {
      return;
    }

    if (mode == 'sync') {
      final database = LocalAttendanceDatabase.openAtPath(dbPath);
      await BootstrapSyncService(
        database: database,
        baseUri: Uri.parse(backendUrl ?? 'http://127.0.0.1:8000'),
      ).sync();
      database.close();
      return;
    }

    if (mode == 'offline') {
      final database = LocalAttendanceDatabase.openAtPath(dbPath);
      addTearDown(database.close);

      expect(database.getCurrentStudent()?.rollNumber, 'DEV24155001');
      expect(database.getCourseSummaries().map((item) => item.courseCode), {
        'CN',
        'DAA',
      });
      expect(database.getAttendanceHistory(), hasLength(4));
      expect(database.getOverallForecast().currentPercentage, 75.0);
      expect(
        database.getOverallForecast().classesToAttendToReachThreshold,
        0,
      );
      return;
    }

    fail('Unknown GOAL02_MODE: $mode');
  });
}
