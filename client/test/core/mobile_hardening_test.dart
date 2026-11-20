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

  Map<String, dynamic> accepted(String id) => {
        'proof_id': id,
        'result': 'ACCEPTED',
        'attendance_record_id': 'rec-$id',
        'attendance_method': 'SECURE_PROOF',
        'recorded_at': '2026-09-02T10:00:01Z',
      };

  OutboxProbe probe(LocalAttendanceDatabase db, String id) {
    final rows = db.pendingProofOutboxEntries(
      now: '2999-01-01T00:00:00Z',
      force: true,
    );
    final match = rows.where((e) => e.proofId == id);
    return OutboxProbe(match.isEmpty ? null : match.single);
  }

  test('per-proof results: permanent rejection does not block the rest',
      () async {
    final database = LocalAttendanceDatabase.inMemory();
    addTearDown(database.close);
    database.applyBootstrap(sampleBootstrapPayload());
    for (final id in ['p-ok', 'p-conflict', 'p-temp']) {
      _enqueueProof(database, id);
    }
    final service = AttendanceProofSyncService(
      database: database,
      baseUri: Uri.parse('https://attendance.example'),
      client: MockClient((_) async => http.Response(
            jsonEncode({
              'results': [
                accepted('p-ok'),
                {
                  'proof_id': 'p-conflict',
                  'result': 'REJECTED',
                  'error_code': 'CLAIM_CONFLICT',
                  'retryable': false,
                },
                {
                  'proof_id': 'p-temp',
                  'result': 'REJECTED',
                  'error_code': 'TEMPORARY_DATABASE_ERROR',
                  'retryable': true,
                },
              ],
            }),
            200,
          )),
    );

    final report = await service.syncPendingProofs(force: true);

    expect(report.accepted, 1);
    expect(report.rejected, 1);
    expect(report.retryPending, 1);
    final pending = probe(database, 'p-temp').entry!;
    expect(pending.state, 'RETRY_PENDING');
    expect(pending.lastErrorCode, 'TEMPORARY_DATABASE_ERROR');
    expect(probe(database, 'p-ok').entry, isNull);
    expect(probe(database, 'p-conflict').entry, isNull);
  });

  test('HTTP 429 honours Retry-After when longer than the backoff', () async {
    final database = LocalAttendanceDatabase.inMemory();
    addTearDown(database.close);
    database.applyBootstrap(sampleBootstrapPayload());
    _enqueueProof(database, 'p-429');
    final service = AttendanceProofSyncService(
      database: database,
      baseUri: Uri.parse('https://attendance.example'),
      client: MockClient(
          (_) async => http.Response('', 429, headers: {'retry-after': '600'})),
    );

    await service.syncPendingProofs(force: true);

    final entry = probe(database, 'p-429').entry!;
    expect(entry.lastErrorCode, 'HTTP_429');
    final next = DateTime.parse(entry.nextAttemptAt!);
    expect(
      next.isAfter(DateTime.now().toUtc().add(const Duration(seconds: 590))),
      isTrue,
    );
  });

  test('a whole-batch HTTP 500 backs off every proof', () async {
    final database = LocalAttendanceDatabase.inMemory();
    addTearDown(database.close);
    database.applyBootstrap(sampleBootstrapPayload());
    _enqueueProof(database, 'p-500');
    final service = AttendanceProofSyncService(
      database: database,
      baseUri: Uri.parse('https://attendance.example'),
      client: MockClient((_) async => http.Response('boom', 500)),
    );

    final report = await service.syncPendingProofs(force: true);

    expect(report.retryPending, 1);
    expect(probe(database, 'p-500').entry!.lastErrorCode, 'HTTP_500');
  });

  test('an interrupted sync is recovered when the local database reopens', () {
    final directory =
        Directory.systemTemp.createTempSync('offlineqr_mobile_hardening_');
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

final _sessionSlots = <String, int>{};

void _enqueueProof(LocalAttendanceDatabase database, String proofId) {
  const now = '2026-09-02T10:00:00Z';
  const studentId = '50000000-0000-4000-8000-000000000001';
  // The local store keeps one claim per (session, student), so each enqueued
  // proof uses its own fixture session (the fixture has three).
  final sessionNumber =
      _sessionSlots.putIfAbsent(proofId, () => _sessionSlots.length % 3 + 1);
  final sessionId = '80000000-0000-4000-8000-00000000000$sessionNumber';
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

class OutboxProbe {
  const OutboxProbe(this.entry);
  final AttendanceProofOutboxEntry? entry;
}
