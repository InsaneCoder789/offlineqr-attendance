import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:client/core/database/local_database.dart';

import '../support/bootstrap_fixture.dart';

void main() {
  test('migration creates schema version 1', () {
    final database = LocalAttendanceDatabase.inMemory();
    addTearDown(database.close);

    expect(database.getCourseSummaries(), isEmpty);
  });

  test('bootstrap sync is idempotent', () {
    final database = LocalAttendanceDatabase.inMemory();
    addTearDown(database.close);

    final payload = sampleBootstrapPayload();
    database.applyBootstrap(payload);
    database.applyBootstrap(payload);

    final summaries = database.getCourseSummaries();
    expect(summaries, hasLength(1));
    expect(summaries.single.courseCode, 'DAA');
    expect(summaries.single.totalClasses, 3);
    expect(summaries.single.present, 2);
    expect(summaries.single.absent, 1);
    expect(summaries.single.percentage, 66.67);
  });

  test('file-backed database supports offline read after restart', () {
    final directory = Directory.systemTemp.createTempSync('kiit_goal02_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final dbPath = '${directory.path}/offline.sqlite';

    final firstOpen = LocalAttendanceDatabase.openAtPath(dbPath);
    firstOpen.applyBootstrap(sampleBootstrapPayload());
    firstOpen.close();

    final secondOpen = LocalAttendanceDatabase.openAtPath(dbPath);
    addTearDown(secondOpen.close);

    final student = secondOpen.getCurrentStudent();
    expect(student?.rollNumber, 'DEV24155001');
    expect(secondOpen.getAttendanceHistory(), hasLength(3));
    expect(secondOpen.getOverallForecast().classesToAttendToReachThreshold, 1);
  });

  test('attendance proof and outbox entry survive restart atomically', () {
    final directory = Directory.systemTemp.createTempSync('kiit_goal07_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final dbPath = '${directory.path}/offline.sqlite';
    const now = '2026-08-20T08:10:13Z';

    final firstOpen = LocalAttendanceDatabase.openAtPath(dbPath);
    firstOpen.applyBootstrap(sampleBootstrapPayload());
    firstOpen.saveAttendanceClaim(
      const AttendanceClaimProjection(
        claimId: 'claim-goal07',
        sessionId: '80000000-0000-4000-8000-000000000001',
        studentId: '50000000-0000-4000-8000-000000000001',
        deviceRegistrationId: 'device-goal07',
        qrEpoch: 1,
        qrChallenge: 'qr-challenge',
        qrIssuedAt: '2026-08-20T08:10:10Z',
        qrExpiresAt: '2026-08-20T08:10:15Z',
        qrSignature: 'qr-signature',
        qrCapturedAt: now,
        claimCreatedAt: now,
        claimExpiresAt: '2026-08-20T08:11:13Z',
        claimState: 'PROOF_READY',
        deviceSignature: 'claim-signature',
      ),
    );
    firstOpen.saveProofAndEnqueueOutbox(
      proofId: 'proof-goal07',
      claimId: 'claim-goal07',
      sessionId: '80000000-0000-4000-8000-000000000001',
      studentId: '50000000-0000-4000-8000-000000000001',
      deviceRegistrationId: 'device-goal07',
      payloadJson: '{"protocol_version":"ATTENDANCE_PROOF_V1"}',
      createdAt: now,
    );
    firstOpen.close();

    final secondOpen = LocalAttendanceDatabase.openAtPath(dbPath);
    addTearDown(secondOpen.close);
    final pending = secondOpen.pendingProofOutboxEntries(limit: 20, now: now);

    expect(pending, hasLength(1));
    expect(pending.single.proofId, 'proof-goal07');
    expect(pending.single.state, 'QUEUED');
    expect(pending.single.attemptCount, 0);
  });
}
