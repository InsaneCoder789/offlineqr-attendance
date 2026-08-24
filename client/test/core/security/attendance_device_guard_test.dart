import 'package:flutter_test/flutter_test.dart';

import 'package:client/core/database/local_database.dart';
import 'package:client/core/security/attendance_device_guard.dart';
import 'package:client/core/security/device_crypto.dart';

import '../../support/bootstrap_fixture.dart';

void main() {
  test('guard reports not registered before projection exists', () async {
    final database = LocalAttendanceDatabase.inMemory();
    addTearDown(database.close);
    database.applyBootstrap(sampleBootstrapPayload());

    final outcome = await AttendanceDeviceGuard(
      database: database,
      keyStore: InMemoryDeviceKeyStore(),
    ).check(studentId: '50000000-0000-4000-8000-000000000001');

    expect(outcome, AttendanceDeviceGuardOutcome.notRegistered);
  });

  test('guard reports ready when key and active projection exist', () async {
    final database = LocalAttendanceDatabase.inMemory();
    addTearDown(database.close);
    database.applyBootstrap(sampleBootstrapPayload());
    database.saveDeviceProjection(
      const DeviceRegistrationProjection(
        deviceRegistrationId: 'device-1',
        studentId: '50000000-0000-4000-8000-000000000001',
        status: 'ACTIVE',
        keyFingerprint: 'abc123',
        platform: 'Android',
        displayLabel: 'Android Device',
        lastVerifiedAt: null,
        serverVersion: 1,
      ),
    );
    final keyStore = InMemoryDeviceKeyStore(seed: List.filled(32, 1));

    final outcome = await AttendanceDeviceGuard(
      database: database,
      keyStore: keyStore,
    ).check(studentId: '50000000-0000-4000-8000-000000000001');

    expect(outcome, AttendanceDeviceGuardOutcome.ready);
  });

  test('guard reports key missing instead of generating replacement', () async {
    final database = LocalAttendanceDatabase.inMemory();
    addTearDown(database.close);
    database.applyBootstrap(sampleBootstrapPayload());
    database.saveDeviceProjection(
      const DeviceRegistrationProjection(
        deviceRegistrationId: 'device-1',
        studentId: '50000000-0000-4000-8000-000000000001',
        status: 'ACTIVE',
        keyFingerprint: 'abc123',
        platform: 'Android',
        displayLabel: 'Android Device',
        lastVerifiedAt: null,
        serverVersion: 1,
      ),
    );

    final outcome = await AttendanceDeviceGuard(
      database: database,
      keyStore: InMemoryDeviceKeyStore(),
    ).check(studentId: '50000000-0000-4000-8000-000000000001');

    expect(outcome, AttendanceDeviceGuardOutcome.keyMissing);
  });

  test('guard detects same installation bound to another student', () async {
    final database = LocalAttendanceDatabase.inMemory();
    addTearDown(database.close);
    database.applyBootstrap(sampleBootstrapPayload());
    database.saveDeviceProjection(
      const DeviceRegistrationProjection(
        deviceRegistrationId: 'device-1',
        studentId: '50000000-0000-4000-8000-000000000001',
        status: 'ACTIVE',
        keyFingerprint: 'abc123',
        platform: 'Android',
        displayLabel: 'Android Device',
        lastVerifiedAt: null,
        serverVersion: 1,
      ),
    );

    final outcome = await AttendanceDeviceGuard(
      database: database,
      keyStore: InMemoryDeviceKeyStore(seed: List.filled(32, 1)),
    ).check(studentId: 'student-b');

    expect(outcome, AttendanceDeviceGuardOutcome.bindingConflict);
  });
}
