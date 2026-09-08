import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:client/core/attendance/attendance_qr_protocol.dart';
import 'package:client/core/database/local_database.dart';
import 'package:client/core/sync/attendance_proof_sync_service.dart';

import '../support/bootstrap_fixture.dart';

void main() {
  test(
      'rejects malformed and oversized QR payloads without throwing a parser error',
      () {
    expect(
      () => AttendanceQrPayload.parse('not-json'),
      throwsA(isA<AttendanceQrException>()),
    );
    expect(
      () => AttendanceQrPayload.parse('x' * 16385),
      throwsA(isA<AttendanceQrException>()),
    );
  });

  test('a missing server batch result returns the proof to the durable outbox',
      () async {
    final database = LocalAttendanceDatabase.inMemory();
    addTearDown(database.close);
    database.applyBootstrap(sampleBootstrapPayload());
    _enqueueProof(database, 'proof-missing-result');
    final service = AttendanceProofSyncService(
      database: database,
      baseUri: Uri.parse('https://attendance.example'),
      client: MockClient(
          (_) async => http.Response(jsonEncode({'results': []}), 200)),
    );

    final report = await service.syncPendingProofs(force: true);

    expect(report.accepted, 0);
    expect(report.retryPending, 1);
    expect(
      database
          .pendingProofOutboxEntries(
            now: DateTime.now()
                .toUtc()
                .add(const Duration(days: 1))
                .toIso8601String(),
            force: true,
          )
          .single
          .lastErrorCode,
      'MISSING_BATCH_RESULT',
    );
  });

  test('an interrupted sync is recovered when the local database reopens', () {
    final directory =
        Directory.systemTemp.createTempSync('kiit_mobile_hardening_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}/attendance.sqlite';
    final first = LocalAttendanceDatabase.openAtPath(path);
    first.applyBootstrap(sampleBootstrapPayload());
    _enqueueProof(first, 'proof-interrupted-sync');
    first.markProofSyncing('proof-interrupted-sync', '2026-09-02T10:00:00Z');
    first.close();

    final reopened = LocalAttendanceDatabase.openAtPath(path);
    addTearDown(reopened.close);
    final recovered = reopened.pendingProofOutboxEntries(
      now: '2026-09-03T10:00:00Z',
      force: true,
    );
    expect(recovered, hasLength(1));
    expect(recovered.single.lastErrorCode, 'INTERRUPTED_SYNC');
  });
}

void _enqueueProof(LocalAttendanceDatabase database, String proofId) {
  const now = '2026-09-02T10:00:00Z';
  const studentId = '50000000-0000-4000-8000-000000000001';
  const sessionId = '80000000-0000-4000-8000-000000000001';
  final claimId = 'claim-$proofId';
  database.saveAttendanceClaim(
    AttendanceClaimProjection(
      claimId: claimId,
      sessionId: sessionId,
      studentId: studentId,
      deviceRegistrationId: 'device-1',
      qrEpoch: 1,
      qrChallenge: 'challenge',
      qrIssuedAt: now,
      qrExpiresAt: '2026-09-02T10:00:05Z',
      qrSignature: 'signature',
      qrCapturedAt: now,
      claimCreatedAt: now,
      claimExpiresAt: '2026-09-02T10:01:00Z',
      claimState: 'PROOF_READY',
      deviceSignature: 'device-signature',
    ),
  );
  database.saveProofAndEnqueueOutbox(
    proofId: proofId,
    claimId: claimId,
    sessionId: sessionId,
    studentId: studentId,
    deviceRegistrationId: 'device-1',
    payloadJson: jsonEncode({'protocol_version': 'ATTENDANCE_PROOF_V1'}),
    createdAt: now,
  );
}
