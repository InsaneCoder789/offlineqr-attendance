import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/core/attendance/attendance_qr_protocol.dart';
import 'package:client/core/database/local_database.dart';
import 'package:client/core/security/device_crypto.dart';
import 'package:client/core/security/encoding.dart';

import '../support/bootstrap_fixture.dart';

void main() {
  test('verifies shared backend QR fixture canonical strings', () async {
    final fixture = jsonDecode(
      File('../shared/fixtures/attendance_qr_v1_vector.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    final payload = AttendanceQrPayload.parse(jsonEncode(fixture['payload']));
    const verifier = AttendanceQrVerifier(
      clock: _fixtureClock,
    );

    expect(
      canonicalSessionAuthorization(payload.authorization),
      fixture['canonical_session_authorization'],
    );
    expect(canonicalAttendanceQr(payload), fixture['canonical_attendance_qr']);
    await verifier.verify(payload);
  });

  test('verifies signed QR and persists proof-ready attendance', () async {
    final database = LocalAttendanceDatabase.inMemory();
    addTearDown(database.close);
    database.applyBootstrap(sampleBootstrapPayload());
    const deviceId = '11111111-1111-4111-8111-111111111111';
    database.saveDeviceProjection(
      const DeviceRegistrationProjection(
        deviceRegistrationId: deviceId,
        studentId: '50000000-0000-4000-8000-000000000001',
        status: 'ACTIVE',
        keyFingerprint: 'abc123',
        platform: 'Android',
        displayLabel: 'Test Device',
        lastVerifiedAt: null,
        serverVersion: 1,
      ),
    );

    final rawQr = await _signedQr(
      issuedAt: DateTime.utc(2026, 8, 18, 10),
      expiresAt: DateTime.utc(2026, 8, 18, 10, 0, 5),
    );
    final service = AttendanceClaimService(
      database: database,
      keyStore: InMemoryDeviceKeyStore(seed: List.filled(32, 7)),
      verifier: AttendanceQrVerifier(
        clock: () => DateTime.utc(2026, 8, 18, 10, 0, 2),
      ),
    );

    final first = await service.capture(rawQr);
    final second = await service.capture(rawQr);

    expect(first.claimId, second.claimId);
    expect(first.alreadyScanned, isFalse);
    expect(second.alreadyScanned, isTrue);
    expect(first.claimState, 'PROOF_READY');
    expect(first.courseCode, 'DAA');
    expect(first.sectionCode, 'CSE-21');
    expect(database.getClaimForSession(first.sessionId, first.studentId),
        isNotNull);
    expect(
        database.pendingProofOutboxEntries(
          limit: 20,
          now: DateTime.now()
              .toUtc()
              .add(const Duration(seconds: 1))
              .toIso8601String(),
        ),
        hasLength(1));
    expect(database.getAttendanceHistory().first.status, 'PRESENT');
  });

  test('rejects expired QR without creating a claim', () async {
    final database = LocalAttendanceDatabase.inMemory();
    addTearDown(database.close);
    database.applyBootstrap(sampleBootstrapPayload());
    final rawQr = await _signedQr(
      issuedAt: DateTime.utc(2026, 8, 18, 10),
      expiresAt: DateTime.utc(2026, 8, 18, 10, 0, 5),
    );
    final service = AttendanceClaimService(
      database: database,
      keyStore: InMemoryDeviceKeyStore(seed: List.filled(32, 7)),
      verifier: AttendanceQrVerifier(
        clock: () => DateTime.utc(2026, 8, 18, 10, 0, 8),
      ),
    );

    expect(
      () => service.capture(rawQr),
      throwsA(isA<AttendanceQrException>()),
    );
  });
}

DateTime _fixtureClock() => DateTime.utc(2026, 8, 18, 10, 0, 2);

Future<String> _signedQr({
  required DateTime issuedAt,
  required DateTime expiresAt,
}) async {
  const sessionId = '80000000-0000-4000-8000-000000000099';
  const offeringId = '60000000-0000-4000-8000-000000000001';
  const facultyId = '40000000-0000-4000-8000-000000000001';
  const authorizationId = 'aaaaaaaa-0000-4000-8000-000000000001';
  const keyId = 'session:$sessionId';
  final algorithm = Ed25519();
  final root = await algorithm.newKeyPairFromSeed(List.filled(32, 17));
  final sessionKey = await algorithm.newKeyPairFromSeed(List.filled(32, 9));
  final sessionPublic = base64UrlNoPadding(
    (await sessionKey.extractPublicKey()).bytes,
  );
  final authorization = SessionAuthorization(
    authorizationId: authorizationId,
    sessionId: sessionId,
    courseOfferingId: offeringId,
    facultyId: facultyId,
    validFrom: DateTime.utc(2026, 8, 18, 9, 45),
    validUntil: DateTime.utc(2026, 8, 18, 11, 15),
    validFromText: DateTime.utc(2026, 8, 18, 9, 45).toIso8601String(),
    validUntilText: DateTime.utc(2026, 8, 18, 11, 15).toIso8601String(),
    keyId: keyId,
    sessionPublicKey: sessionPublic,
    serverSignature: '',
  );
  final rootSignature = await algorithm.sign(
    utf8.encode(canonicalSessionAuthorization(authorization)),
    keyPair: root,
  );
  final signedAuthorization = SessionAuthorization(
    authorizationId: authorization.authorizationId,
    sessionId: authorization.sessionId,
    courseOfferingId: authorization.courseOfferingId,
    facultyId: authorization.facultyId,
    validFrom: authorization.validFrom,
    validUntil: authorization.validUntil,
    validFromText: authorization.validFromText,
    validUntilText: authorization.validUntilText,
    keyId: authorization.keyId,
    sessionPublicKey: authorization.sessionPublicKey,
    serverSignature: base64UrlNoPadding(rootSignature.bytes),
  );
  final qr = AttendanceQrPayload(
    sessionId: sessionId,
    epoch: 0,
    issuedAt: issuedAt,
    expiresAt: expiresAt,
    issuedAtText: issuedAt.toIso8601String(),
    expiresAtText: expiresAt.toIso8601String(),
    challenge: 'challenge-001',
    keyId: keyId,
    signature: '',
    authorization: signedAuthorization,
  );
  final qrSignature = await algorithm.sign(
    utf8.encode(canonicalAttendanceQr(qr)),
    keyPair: sessionKey,
  );
  return jsonEncode({
    'protocol_version': attendanceQrProtocol,
    'session_id': sessionId,
    'epoch': 0,
    'issued_at': issuedAt.toIso8601String(),
    'expires_at': expiresAt.toIso8601String(),
    'challenge': qr.challenge,
    'key_id': keyId,
    'signature': base64UrlNoPadding(qrSignature.bytes),
    'session_authorization': {
      'authorization_id': signedAuthorization.authorizationId,
      'protocol_version': sessionAuthorizationProtocol,
      'session_id': signedAuthorization.sessionId,
      'course_offering_id': signedAuthorization.courseOfferingId,
      'faculty_id': signedAuthorization.facultyId,
      'valid_from': signedAuthorization.validFrom.toIso8601String(),
      'valid_until': signedAuthorization.validUntil.toIso8601String(),
      'key_id': signedAuthorization.keyId,
      'session_public_key': signedAuthorization.sessionPublicKey,
      'server_signature': signedAuthorization.serverSignature,
    },
  });
}
