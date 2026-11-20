import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:client/core/database/local_database.dart';
import 'package:client/core/sync/bootstrap_sync_service.dart';

void main() {
  test('sync once, stop server, reopen database, read offline', () async {
    final fixture = File('../shared/fixtures/bootstrap_dev_student.json')
        .readAsStringSync();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serverDone = server.listen((request) {
      if (request.uri.path == '/api/v1/sync/bootstrap') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(fixture);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      request.response.close();
    });

    final directory = Directory.systemTemp.createTempSync('offlineqr_sync_goal02_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final dbPath = '${directory.path}/offline.sqlite';

    final onlineOpen = LocalAttendanceDatabase.openAtPath(dbPath);
    await BootstrapSyncService(
      database: onlineOpen,
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
    ).sync();
    onlineOpen.close();
    await server.close(force: true);
    await serverDone.cancel();

    final offlineOpen = LocalAttendanceDatabase.openAtPath(dbPath);
    addTearDown(offlineOpen.close);

    expect(offlineOpen.getCurrentStudent()?.rollNumber, 'DEV24155001');
    expect(offlineOpen.getCourseSummaries().single.percentage, 66.67);
    expect(offlineOpen.getAttendanceHistory(), hasLength(3));
    expect(
      offlineOpen.getOverallForecast().classesToAttendToReachThreshold,
      1,
    );
  });
}
