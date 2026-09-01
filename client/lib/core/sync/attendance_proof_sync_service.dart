import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../attendance/attendance_qr_protocol.dart';
import '../database/local_database.dart';
import '../network/api_config.dart';
import '../security/device_crypto.dart';

const int proofSyncBatchLimit = 20;

class AttendanceProofSyncReport {
  const AttendanceProofSyncReport({
    required this.submitted,
    required this.accepted,
    required this.retryPending,
    required this.rejected,
    required this.repaired,
  });

  final int submitted;
  final int accepted;
  final int retryPending;
  final int rejected;
  final int repaired;

  bool get hasFailures => retryPending > 0 || rejected > 0;
}

class AttendanceProofSyncService {
  AttendanceProofSyncService({
    required this.database,
    required this.baseUri,
    this.keyStore,
    http.Client? client,
    Random? random,
  })  : _client = client,
        _random = random ?? Random.secure();

  final LocalAttendanceDatabase database;
  final Uri baseUri;
  final DeviceKeyStore? keyStore;
  final http.Client? _client;
  final Random _random;

  Future<AttendanceProofSyncReport> syncPendingProofs(
      {bool force = false}) async {
    final now = canonicalUtcTimestamp(DateTime.now());
    final repaired = await _repairRejectedProofs();
    final entries = database.pendingProofOutboxEntries(
      limit: proofSyncBatchLimit,
      now: now,
      force: force,
    );
    if (entries.isEmpty) {
      return AttendanceProofSyncReport(
        submitted: 0,
        accepted: 0,
        retryPending: 0,
        rejected: 0,
        repaired: repaired,
      );
    }

    for (final entry in entries) {
      database.markProofSyncing(entry.proofId, now);
    }

    final client = _client ?? http.Client();
    try {
      final response = await client
          .post(
            baseUri.resolve('/api/v1/attendance/proofs/batch'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({
              'proofs': [
                for (final entry in entries)
                  jsonDecode(entry.payloadJson) as Map<String, dynamic>,
              ],
            }),
          )
          .timeout(apiRequestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _markBatchRetry(entries, 'HTTP_${response.statusCode}');
        return AttendanceProofSyncReport(
          submitted: entries.length,
          accepted: 0,
          retryPending: entries.length,
          rejected: 0,
          repaired: repaired,
        );
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final results =
          (body['results'] as List<dynamic>).cast<Map<String, dynamic>>();
      final entriesByProofId = {
        for (final entry in entries) entry.proofId: entry
      };
      var accepted = 0;
      var retryPending = 0;
      var rejected = 0;
      for (final result in results) {
        final proofId = result['proof_id'] as String;
        final entry = entriesByProofId[proofId];
        if (entry == null) continue;
        final resultName = result['result'] as String;
        if (resultName == 'ACCEPTED' || resultName == 'ALREADY_ACCEPTED') {
          database.markProofAccepted(
            proofId: proofId,
            attendanceRecordId: result['attendance_record_id'] as String,
            sessionId: entry.sessionId,
            studentId: entry.studentId,
            deviceRegistrationId: entry.deviceRegistrationId,
            method: result['attendance_method'] as String,
            recordedAt: result['recorded_at'] as String,
            now: canonicalUtcTimestamp(DateTime.now()),
          );
          accepted++;
        } else if (result['retryable'] == true) {
          database.markProofRetryPending(
            proofId: proofId,
            nextAttemptAt: _nextAttemptAt(entry.attemptCount + 1),
            now: canonicalUtcTimestamp(DateTime.now()),
            errorCode: result['error_code'] as String? ?? 'RETRYABLE_ERROR',
          );
          retryPending++;
        } else {
          database.markProofRejected(
            proofId: proofId,
            now: canonicalUtcTimestamp(DateTime.now()),
            errorCode: result['error_code'] as String? ?? 'SERVER_REJECTED',
          );
          rejected++;
        }
      }
      return AttendanceProofSyncReport(
        submitted: entries.length,
        accepted: accepted,
        retryPending: retryPending,
        rejected: rejected,
        repaired: repaired,
      );
    } catch (_) {
      _markBatchRetry(entries, 'NETWORK_UNAVAILABLE');
      return AttendanceProofSyncReport(
        submitted: entries.length,
        accepted: 0,
        retryPending: entries.length,
        rejected: 0,
        repaired: repaired,
      );
    } finally {
      if (_client == null) {
        client.close();
      }
    }
  }

  Future<int> _repairRejectedProofs() async {
    // Never mutate a signed proof after capture. A replacement device must not
    // be able to impersonate the device that observed the classroom QR.
    return 0;
  }

  void _markBatchRetry(List<AttendanceProofOutboxEntry> entries, String code) {
    final now = canonicalUtcTimestamp(DateTime.now());
    for (final entry in entries) {
      database.markProofRetryPending(
        proofId: entry.proofId,
        nextAttemptAt: _nextAttemptAt(entry.attemptCount + 1),
        now: now,
        errorCode: code,
      );
    }
  }

  String _nextAttemptAt(int attemptCount) {
    final cappedAttempt = attemptCount.clamp(1, 6);
    final baseSeconds = 5 * (1 << (cappedAttempt - 1));
    final jitterSeconds = _random.nextInt(baseSeconds + 1);
    return canonicalUtcTimestamp(
      DateTime.now()
          .toUtc()
          .add(Duration(seconds: baseSeconds + jitterSeconds)),
    );
  }
}
