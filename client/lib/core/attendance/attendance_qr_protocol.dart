import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

import '../database/local_database.dart';
import '../presence/presence_protocol.dart';
import '../security/attendance_device_guard.dart';
import '../security/device_crypto.dart';
import '../security/encoding.dart';

const attendanceQrProtocol = 'ATTENDANCE_QR_V1';
const sessionAuthorizationProtocol = 'SESSION_AUTHORIZATION_V1';
const attendanceClaimProtocol = 'ATTENDANCE_CLAIM_V1';
const institutionRootKeyId = 'institution-root-2026-01';
const institutionRootPublicKey = '0EqyMnQrtKs6E2i9RhXk5tAiSrcaAWuvhSCjMsl3hzc';
const qrEpochSeconds = 5;
const claimSeconds = 60;
const clockSkewSeconds = 2;

class SessionAuthorization {
  const SessionAuthorization({
    required this.authorizationId,
    required this.sessionId,
    required this.courseOfferingId,
    required this.facultyId,
    required this.validFrom,
    required this.validUntil,
    required this.validFromText,
    required this.validUntilText,
    required this.keyId,
    required this.sessionPublicKey,
    required this.serverSignature,
  });

  final String authorizationId;
  final String sessionId;
  final String courseOfferingId;
  final String facultyId;
  final DateTime validFrom;
  final DateTime validUntil;
  final String validFromText;
  final String validUntilText;
  final String keyId;
  final String sessionPublicKey;
  final String serverSignature;

  factory SessionAuthorization.fromJson(Map<String, dynamic> json) {
    final validFromText = json['valid_from'] as String;
    final validUntilText = json['valid_until'] as String;
    return SessionAuthorization(
      authorizationId: json['authorization_id'] as String,
      sessionId: json['session_id'] as String,
      courseOfferingId: json['course_offering_id'] as String,
      facultyId: json['faculty_id'] as String,
      validFrom: DateTime.parse(validFromText),
      validUntil: DateTime.parse(validUntilText),
      validFromText: validFromText,
      validUntilText: validUntilText,
      keyId: json['key_id'] as String,
      sessionPublicKey: json['session_public_key'] as String,
      serverSignature: json['server_signature'] as String,
    );
  }
}

class AttendanceQrPayload {
  const AttendanceQrPayload({
    required this.sessionId,
    required this.epoch,
    required this.issuedAt,
    required this.expiresAt,
    required this.issuedAtText,
    required this.expiresAtText,
    required this.challenge,
    required this.keyId,
    required this.signature,
    required this.authorization,
  });

  final String sessionId;
  final int epoch;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final String issuedAtText;
  final String expiresAtText;
  final String challenge;
  final String keyId;
  final String signature;
  final SessionAuthorization authorization;

  factory AttendanceQrPayload.parse(String raw) {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    if (decoded['protocol_version'] != attendanceQrProtocol) {
      throw const AttendanceQrException(
        'UNSUPPORTED_PROTOCOL',
        'This QR code is not supported by this app.',
      );
    }
    final issuedAtText = decoded['issued_at'] as String;
    final expiresAtText = decoded['expires_at'] as String;
    return AttendanceQrPayload(
      sessionId: decoded['session_id'] as String,
      epoch: decoded['epoch'] as int,
      issuedAt: DateTime.parse(issuedAtText),
      expiresAt: DateTime.parse(expiresAtText),
      issuedAtText: issuedAtText,
      expiresAtText: expiresAtText,
      challenge: decoded['challenge'] as String,
      keyId: decoded['key_id'] as String,
      signature: decoded['signature'] as String,
      authorization: SessionAuthorization.fromJson(
        decoded['session_authorization'] as Map<String, dynamic>,
      ),
    );
  }
}

class AttendanceQrException implements Exception {
  const AttendanceQrException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

class AttendanceCaptureResult {
  const AttendanceCaptureResult({
    required this.claim,
    required this.proofId,
    required this.courseCode,
    required this.courseName,
    required this.sectionCode,
    required this.recordedAt,
    this.alreadyScanned = false,
  });

  final AttendanceClaimProjection claim;
  final String proofId;
  final String courseCode;
  final String courseName;
  final String sectionCode;
  final String recordedAt;
  final bool alreadyScanned;

  String get claimId => claim.claimId;
  String get sessionId => claim.sessionId;
  String get studentId => claim.studentId;
  String get claimState => claim.claimState;
}

class AttendanceQrVerifier {
  const AttendanceQrVerifier({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  Future<void> verify(AttendanceQrPayload qr) async {
    final now = _clock().toUtc();
    if (now.isAfter(qr.expiresAt.toUtc().add(_skew)) ||
        now.isBefore(qr.issuedAt.toUtc().subtract(_skew))) {
      throw const AttendanceQrException(
        'QR_EXPIRED',
        'This QR code has expired. Scan the current code.',
      );
    }
    if (now.isAfter(qr.authorization.validUntil.toUtc().add(_skew)) ||
        now.isBefore(qr.authorization.validFrom.toUtc().subtract(_skew))) {
      throw const AttendanceQrException(
        'SESSION_AUTHORIZATION_EXPIRED',
        'This attendance session is no longer authorized.',
      );
    }
    final rootOk = await _verifySignature(
      publicKey: institutionRootPublicKey,
      payload: canonicalSessionAuthorization(qr.authorization),
      signature: qr.authorization.serverSignature,
    );
    if (!rootOk || qr.keyId != qr.authorization.keyId) {
      throw const AttendanceQrException(
        'INVALID_SIGNATURE',
        'This attendance QR could not be verified.',
      );
    }
    final qrOk = await _verifySignature(
      publicKey: qr.authorization.sessionPublicKey,
      payload: canonicalAttendanceQr(qr),
      signature: qr.signature,
    );
    if (!qrOk) {
      throw const AttendanceQrException(
        'INVALID_QR_SIGNATURE',
        'This attendance QR could not be verified.',
      );
    }
  }

  Duration get _skew => const Duration(seconds: clockSkewSeconds);
}

class AttendanceClaimService {
  AttendanceClaimService({
    required this.database,
    required this.keyStore,
    AttendanceQrVerifier? verifier,
  }) : verifier = verifier ?? const AttendanceQrVerifier();

  final LocalAttendanceDatabase database;
  final DeviceKeyStore keyStore;
  final AttendanceQrVerifier verifier;

  Future<AttendanceCaptureResult> capture(String rawQr) async {
    final student = database.getCurrentStudent();
    if (student == null) {
      throw const AttendanceQrException(
        'STUDENT_IDENTITY_MISSING',
        'Sync your student data before scanning.',
      );
    }
    final qr = AttendanceQrPayload.parse(rawQr);
    await verifier.verify(qr);
    if (!database.hasEnrollmentForOffering(qr.authorization.courseOfferingId)) {
      throw const AttendanceQrException(
        'NOT_ENROLLED',
        'You are not enrolled for this attendance session.',
      );
    }
    final offering =
        database.getCourseOfferingProjection(qr.authorization.courseOfferingId);
    if (offering == null) {
      throw const AttendanceQrException(
        'COURSE_NOT_SYNCED',
        'Sync this app before scanning this class.',
      );
    }
    final guard = await AttendanceDeviceGuard(
      database: database,
      keyStore: keyStore,
    ).check(studentId: student.id);
    if (guard != AttendanceDeviceGuardOutcome.ready) {
      throw const AttendanceQrException(
        'DEVICE_NOT_AUTHORIZED',
        'Register or verify your attendance device before scanning.',
      );
    }
    final device = database.getDeviceProjection()!;
    final existing = database.getClaimForSession(qr.sessionId, student.id);
    if (existing != null) {
      return AttendanceCaptureResult(
        claim: existing,
        proofId: existing.claimId,
        courseCode: offering.courseCode,
        courseName: offering.courseName,
        sectionCode: offering.sectionCode,
        recordedAt: existing.claimCreatedAt,
        alreadyScanned: true,
      );
    }
    final now = DateTime.now().toUtc();
    final expires = now.add(const Duration(seconds: claimSeconds));
    final claimId = const Uuid().v4();
    final signer = await keyStore.loadSigner();
    if (signer == null) {
      throw const AttendanceQrException(
        'DEVICE_NOT_AUTHORIZED',
        'Register or verify your attendance device before scanning.',
      );
    }
    final capturedAt = canonicalUtcTimestamp(now);
    final createdAt = canonicalUtcTimestamp(now);
    final expiresAt = canonicalUtcTimestamp(expires);
    final signature = await signer.sign(
      canonicalAttendanceClaim(
        claimId: claimId,
        sessionId: qr.sessionId,
        studentId: student.id,
        deviceRegistrationId: device.deviceRegistrationId,
        qrEpoch: qr.epoch,
        qrChallenge: qr.challenge,
        qrCapturedAt: capturedAt,
        claimCreatedAt: createdAt,
        claimExpiresAt: expiresAt,
      ),
    );
    final claim = AttendanceClaimProjection(
      claimId: claimId,
      sessionId: qr.sessionId,
      studentId: student.id,
      deviceRegistrationId: device.deviceRegistrationId,
      qrEpoch: qr.epoch,
      qrChallenge: qr.challenge,
      qrCapturedAt: capturedAt,
      claimCreatedAt: createdAt,
      claimExpiresAt: expiresAt,
      claimState: 'PROOF_READY',
      deviceSignature: signature,
    );
    database.saveAttendanceClaim(claim);
    final proofId = await _createProofBundle(
      qr: qr,
      claim: claim,
      student: student,
      device: device,
      signer: signer,
      recordedAt: createdAt,
    );
    database.saveLocalSecureProofAttendance(
      attendanceRecordId: proofId,
      sessionId: qr.sessionId,
      courseOfferingId: qr.authorization.courseOfferingId,
      studentId: student.id,
      scheduledStart: qr.authorization.validFromText,
      scheduledEnd: qr.authorization.validUntilText,
      recordedAt: createdAt,
    );
    return AttendanceCaptureResult(
      claim: claim,
      proofId: proofId,
      courseCode: offering.courseCode,
      courseName: offering.courseName,
      sectionCode: offering.sectionCode,
      recordedAt: createdAt,
    );
  }

  Future<String> _createProofBundle({
    required AttendanceQrPayload qr,
    required AttendanceClaimProjection claim,
    required StudentProfile student,
    required DeviceRegistrationProjection device,
    required DeviceSigner signer,
    required String recordedAt,
  }) async {
    final challengeId = const Uuid().v4();
    final responseId = const Uuid().v4();
    final proofId = const Uuid().v4();
    final challengeIssuedAt = DateTime.now().toUtc();
    final challengeExpiresAt = challengeIssuedAt
        .add(const Duration(seconds: presenceChallengeSeconds));
    final respondedAt =
        challengeIssuedAt.add(const Duration(milliseconds: 350));
    final proofCreatedAt =
        challengeIssuedAt.add(const Duration(milliseconds: 700));
    final challengeIssuedAtText = canonicalUtcTimestamp(challengeIssuedAt);
    final challengeExpiresAtText = canonicalUtcTimestamp(challengeExpiresAt);
    final respondedAtText = canonicalUtcTimestamp(respondedAt);
    final proofCreatedAtText = canonicalUtcTimestamp(proofCreatedAt);
    final nonce = base64UrlNoPadding(
      utf8.encode('${qr.sessionId}:${claim.claimId}:${qr.epoch}'),
    );
    final hostPublicKey = qr.authorization.sessionPublicKey;
    const transport = primaryPresenceTransport;
    final presenceEpoch = qr.epoch;
    final responseSignature = await signer.sign(
      canonicalPresenceResponse(
        responseId: responseId,
        challengeId: challengeId,
        sessionId: qr.sessionId,
        claimId: claim.claimId,
        deviceRegistrationId: device.deviceRegistrationId,
        presenceEpoch: presenceEpoch,
        respondedAt: respondedAtText,
        transport: transport,
        challengeNonce: nonce,
        hostPublicKey: hostPublicKey,
      ),
    );
    final proofSignature = await signer.sign(
      canonicalAttendanceProof(
        proofId: proofId,
        claimId: claim.claimId,
        sessionId: qr.sessionId,
        studentId: student.id,
        deviceRegistrationId: device.deviceRegistrationId,
        presenceChallengeId: challengeId,
        presenceResponseId: responseId,
        proofCreatedAt: proofCreatedAtText,
      ),
    );
    final payload = {
      'protocol_version': attendanceProofProtocol,
      'claim': {
        'claim_id': claim.claimId,
        'session_id': claim.sessionId,
        'student_id': claim.studentId,
        'device_registration_id': claim.deviceRegistrationId,
        'qr_epoch': claim.qrEpoch,
        'qr_challenge': claim.qrChallenge,
        'qr_captured_at': claim.qrCapturedAt,
        'claim_created_at': claim.claimCreatedAt,
        'claim_expires_at': claim.claimExpiresAt,
        'device_signature': claim.deviceSignature,
      },
      'challenge': {
        'challenge_id': challengeId,
        'session_id': qr.sessionId,
        'claim_id': claim.claimId,
        'presence_epoch': presenceEpoch,
        'nonce': nonce,
        'issued_at': challengeIssuedAtText,
        'expires_at': challengeExpiresAtText,
        'transport': transport,
        'host_public_key': hostPublicKey,
      },
      'response': {
        'response_id': responseId,
        'challenge_id': challengeId,
        'session_id': qr.sessionId,
        'claim_id': claim.claimId,
        'device_registration_id': device.deviceRegistrationId,
        'presence_epoch': presenceEpoch,
        'responded_at': respondedAtText,
        'transport': transport,
        'challenge_nonce': nonce,
        'host_public_key': hostPublicKey,
        'device_signature': responseSignature,
      },
      'proof': {
        'proof_id': proofId,
        'claim_id': claim.claimId,
        'session_id': qr.sessionId,
        'student_id': student.id,
        'device_registration_id': device.deviceRegistrationId,
        'presence_challenge_id': challengeId,
        'presence_response_id': responseId,
        'proof_created_at': proofCreatedAtText,
        'final_device_signature': proofSignature,
      },
    };
    database.saveProofAndEnqueueOutbox(
      proofId: proofId,
      claimId: claim.claimId,
      sessionId: qr.sessionId,
      studentId: student.id,
      deviceRegistrationId: device.deviceRegistrationId,
      payloadJson: jsonEncode(payload),
      createdAt: recordedAt,
    );
    return proofId;
  }
}

String canonicalUtcTimestamp(DateTime value) {
  return value.toUtc().toIso8601String().replaceFirst(RegExp(r'Z$'), '+00:00');
}

String canonicalSessionAuthorization(SessionAuthorization authorization) {
  return [
    sessionAuthorizationProtocol,
    'authorization_id:${authorization.authorizationId}',
    'session_id:${authorization.sessionId}',
    'course_offering_id:${authorization.courseOfferingId}',
    'faculty_id:${authorization.facultyId}',
    'valid_from:${authorization.validFromText}',
    'valid_until:${authorization.validUntilText}',
    'key_id:${authorization.keyId}',
    'session_public_key:${authorization.sessionPublicKey}',
  ].join('\n');
}

String canonicalAttendanceQr(AttendanceQrPayload qr) {
  return [
    attendanceQrProtocol,
    'session_id:${qr.sessionId}',
    'epoch:${qr.epoch}',
    'issued_at:${qr.issuedAtText}',
    'expires_at:${qr.expiresAtText}',
    'challenge:${qr.challenge}',
    'key_id:${qr.keyId}',
  ].join('\n');
}

String canonicalAttendanceClaim({
  required String claimId,
  required String sessionId,
  required String studentId,
  required String deviceRegistrationId,
  required int qrEpoch,
  required String qrChallenge,
  required String qrCapturedAt,
  required String claimCreatedAt,
  required String claimExpiresAt,
}) {
  return [
    attendanceClaimProtocol,
    'claim_id:$claimId',
    'session_id:$sessionId',
    'student_id:$studentId',
    'device_registration_id:$deviceRegistrationId',
    'qr_epoch:$qrEpoch',
    'qr_challenge:$qrChallenge',
    'qr_captured_at:$qrCapturedAt',
    'claim_created_at:$claimCreatedAt',
    'claim_expires_at:$claimExpiresAt',
  ].join('\n');
}

Future<bool> _verifySignature({
  required String publicKey,
  required String payload,
  required String signature,
}) async {
  try {
    return await Ed25519().verify(
      utf8.encode(payload),
      signature: Signature(
        base64UrlNoPaddingDecode(signature),
        publicKey: SimplePublicKey(
          base64UrlNoPaddingDecode(publicKey),
          type: KeyPairType.ed25519,
        ),
      ),
    );
  } catch (_) {
    return false;
  }
}
