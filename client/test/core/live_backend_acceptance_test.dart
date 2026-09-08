import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';

import 'package:client/core/database/local_database.dart';
import 'package:client/core/sync/bootstrap_sync_service.dart';

void main() {
  final dbPath = Platform.environment['GOAL02_DB_PATH'];
  final mode = Platform.environment['GOAL02_MODE'];
  final configured = dbPath != null && mode != null;

  test('Goal 02 live backend sync/offline acceptance step', () async {
    final backendUrl = Platform.environment['GOAL02_BACKEND_URL'];
    final studentId = Platform.environment['GOAL02_STUDENT_ID'] ??
        '50000000-0000-4000-8000-000000000001';

    if (mode == 'sync') {
      final database = LocalAttendanceDatabase.openAtPath(dbPath!);
      final client = _DevelopmentIdentityClient(studentId);
      await BootstrapSyncService(
        database: database,
        baseUri: Uri.parse(backendUrl ?? 'http://127.0.0.1:8000'),
        client: client,
      ).sync();
      client.close();
      database.close();
      return;
    }

    if (mode == 'offline') {
      final database = LocalAttendanceDatabase.openAtPath(dbPath!);
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
  },
      skip: configured
          ? false
          : 'Live backend acceptance environment is not configured.');
}

class _DevelopmentIdentityClient extends http.BaseClient {
  _DevelopmentIdentityClient(this.studentId);

  final String studentId;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['X-Student-Id'] = studentId;
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
