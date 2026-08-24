import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:client/core/database/local_database.dart';
import 'package:client/core/sync/bootstrap_models.dart';

void main() {
  test('Dart decodes shared bootstrap sync fixture', () {
    final fixture = File('../shared/fixtures/bootstrap_dev_student.json');
    final payload = BootstrapSyncPayload.fromJson(
      jsonDecode(fixture.readAsStringSync()) as Map<String, dynamic>,
    );

    final database = LocalAttendanceDatabase.inMemory();
    addTearDown(database.close);
    database.applyBootstrap(payload);

    expect(payload.syncVersion, 1);
    expect(payload.student.rollNumber, 'DEV24155001');
    expect(database.getCourseSummaries().single.percentage, 66.67);
  });
}
