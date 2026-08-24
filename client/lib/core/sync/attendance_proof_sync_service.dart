import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../attendance/attendance_qr_protocol.dart';
import '../database/local_database.dart';
import '../network/api_config.dart';
import '../presence/presence_protocol.dart';
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
    final signer = await keyStore?.loadSigner();
    if (signer == null) return 0;
    final entries = database.repairableRejectedOutboxEntries();
    var repaired = 0;
    for (final entry in entries) {
      try {
        final activeDevice = entry.lastErrorCode == 'DEVICE_REVOKED'
            ? await _currentServerDevice(entry.studentId)
            : null;
        if (entry.lastErrorCode == 'DEVICE_REVOKED' && activeDevice == null) {
          continue;
        }
        final payload = jsonDecode(entry.payloadJson) as Map<String, dynamic>;
        final claim = payload['claim'] as Map<String, dynamic>;
        final response = payload['response'] as Map<String, dynamic>;
        final proof = payload['proof'] as Map<String, dynamic>;
        if (activeDevice != null) {
          final activeDeviceId = activeDevice.deviceRegistrationId;
          claim['device_registration_id'] = activeDeviceId;
          response['device_registration_id'] = activeDeviceId;
          proof['device_registration_id'] = activeDeviceId;
          database.saveDeviceProjection(activeDevice);
        }

        claim['qr_captured_at'] = _normalizeTimestamp(claim['qr_captured_at']);
        claim['claim_created_at'] =
            _normalizeTimestamp(claim['claim_created_at']);
        claim['claim_expires_at'] =
            _normalizeTimestamp(claim['claim_expires_at']);
        response['responded_at'] =
            _normalizeTimestamp(response['responded_at']);
        proof['proof_created_at'] =
            _normalizeTimestamp(proof['proof_created_at']);

        claim['device_signature'] = await signer.sign(
          canonicalAttendanceClaim(
            claimId: claim['claim_id'] as String,
            sessionId: claim['session_id'] as String,
            studentId: claim['student_id'] as String,
            deviceRegistrationId: claim['device_registration_id'] as String,
            qrEpoch: claim['qr_epoch'] as int,
            qrChallenge: claim['qr_challenge'] as String,
            qrCapturedAt: claim['qr_captured_at'] as String,
            claimCreatedAt: claim['claim_created_at'] as String,
            claimExpiresAt: claim['claim_expires_at'] as String,
          ),
        );
        response['device_signature'] = await signer.sign(
          canonicalPresenceResponse(
            responseId: response['response_id'] as String,
            challengeId: response['challenge_id'] as String,
            sessionId: response['session_id'] as String,
            claimId: response['claim_id'] as String,
            deviceRegistrationId: response['device_registration_id'] as String,
            presenceEpoch: response['presence_epoch'] as int,
            respondedAt: response['responded_at'] as String,
            transport: response['transport'] as String,
            challengeNonce: response['challenge_nonce'] as String,
            hostPublicKey: response['host_public_key'] as String,
          ),
        );
        proof['final_device_signature'] = await signer.sign(
          canonicalAttendanceProof(
            proofId: proof['proof_id'] as String,
            claimId: proof['claim_id'] as String,
            sessionId: proof['session_id'] as String,
            studentId: proof['student_id'] as String,
            deviceRegistrationId: proof['device_registration_id'] as String,
            presenceChallengeId: proof['presence_challenge_id'] as String,
            presenceResponseId: proof['presence_response_id'] as String,
            proofCreatedAt: proof['proof_created_at'] as String,
          ),
        );
        database.updateProofPayloadAndRequeue(
          proofId: entry.proofId,
          payloadJson: jsonEncode(payload),
          now: canonicalUtcTimestamp(DateTime.now()),
          claimId: claim['claim_id'] as String,
          deviceRegistrationId: proof['device_registration_id'] as String,
        );
        repaired++;
      } catch (_) {
        continue;
      }
    }
    return repaired;
  }

  Future<DeviceRegistrationProjection?> _currentServerDevice(
      String studentId) async {
    final client = _client ?? http.Client();
    try {
      final response = await client.get(
        baseUri.resolve('/api/v1/devices/current'),
        headers: {'X-Student-Id': studentId},
      ).timeout(apiRequestTimeout);
      if (response.statusCode != 200 || response.body == 'null') {
        return null;
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return DeviceRegistrationProjection(
        deviceRegistrationId: body['id'] as String,
        studentId: body['student_id'] as String,
        status: body['status'] as String,
        keyFingerprint: body['key_fingerprint'] as String,
        platform: body['platform'] as String,
        displayLabel: body['display_label'] as String?,
        lastVerifiedAt: body['last_seen_at'] as String?,
        serverVersion: 1,
      );
    } finally {
      if (_client == null) {
        client.close();
      }
    }
  }

  String _normalizeTimestamp(Object? value) {
    final text = value as String;
    final parsed = DateTime.parse(text);
    return canonicalUtcTimestamp(parsed);
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
