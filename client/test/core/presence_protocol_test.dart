import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/core/presence/presence_protocol.dart';
import 'package:client/core/security/device_crypto.dart';
import 'package:client/core/security/encoding.dart';

void main() {
  test('Dart matches shared presence protocol vector', () async {
    final vector = jsonDecode(
      File('../shared/fixtures/presence_v1_vector.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final challenge = vector['challenge'] as Map<String, dynamic>;
    final response = vector['response'] as Map<String, dynamic>;
    final proof = vector['proof'] as Map<String, dynamic>;

    expect(
      canonicalPresenceChallenge(
        challengeId: challenge['challenge_id'] as String,
        sessionId: challenge['session_id'] as String,
        claimId: challenge['claim_id'] as String,
        presenceEpoch: challenge['presence_epoch'] as int,
        nonce: challenge['nonce'] as String,
        issuedAt: challenge['issued_at'] as String,
        expiresAt: challenge['expires_at'] as String,
        transport: challenge['transport'] as String,
        hostPublicKey: challenge['host_public_key'] as String,
      ),
      vector['canonical_presence_challenge'],
    );
    expect(
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
      vector['canonical_presence_response'],
    );
    expect(
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
      vector['canonical_attendance_proof'],
    );

    final signer = DeviceSigner(
      await Ed25519().newKeyPairFromSeed(
        base64UrlNoPaddingDecode(vector['seed_b64url'] as String),
      ),
    );
    expect(
      await signer.sign(vector['canonical_presence_response'] as String),
      vector['presence_response_signature'],
    );
    expect(
      await signer.sign(vector['canonical_attendance_proof'] as String),
      vector['attendance_proof_signature'],
    );
  });
}
