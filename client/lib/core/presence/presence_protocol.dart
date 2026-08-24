const presenceChallengeProtocol = 'PRESENCE_CHALLENGE_V1';
const presenceResponseProtocol = 'PRESENCE_RESPONSE_V1';
const attendanceProofProtocol = 'ATTENDANCE_PROOF_V1';
const presenceEpochSeconds = 10;
const presenceChallengeSeconds = 20;
const primaryPresenceTransport = 'QR_ASSISTED_WEBRTC_DATA_CHANNEL';

String canonicalPresenceChallenge({
  required String challengeId,
  required String sessionId,
  required String claimId,
  required int presenceEpoch,
  required String nonce,
  required String issuedAt,
  required String expiresAt,
  required String transport,
  required String hostPublicKey,
}) {
  return [
    presenceChallengeProtocol,
    'challenge_id:$challengeId',
    'session_id:$sessionId',
    'claim_id:$claimId',
    'presence_epoch:$presenceEpoch',
    'nonce:$nonce',
    'issued_at:$issuedAt',
    'expires_at:$expiresAt',
    'transport:$transport',
    'host_public_key:$hostPublicKey',
  ].join('\n');
}

String canonicalPresenceResponse({
  required String responseId,
  required String challengeId,
  required String sessionId,
  required String claimId,
  required String deviceRegistrationId,
  required int presenceEpoch,
  required String respondedAt,
  required String transport,
  required String challengeNonce,
  required String hostPublicKey,
}) {
  return [
    presenceResponseProtocol,
    'response_id:$responseId',
    'challenge_id:$challengeId',
    'session_id:$sessionId',
    'claim_id:$claimId',
    'device_registration_id:$deviceRegistrationId',
    'presence_epoch:$presenceEpoch',
    'responded_at:$respondedAt',
    'transport:$transport',
    'challenge_nonce:$challengeNonce',
    'host_public_key:$hostPublicKey',
  ].join('\n');
}

String canonicalAttendanceProof({
  required String proofId,
  required String claimId,
  required String sessionId,
  required String studentId,
  required String deviceRegistrationId,
  required String presenceChallengeId,
  required String presenceResponseId,
  required String proofCreatedAt,
}) {
  return [
    attendanceProofProtocol,
    'proof_id:$proofId',
    'claim_id:$claimId',
    'session_id:$sessionId',
    'student_id:$studentId',
    'device_registration_id:$deviceRegistrationId',
    'presence_challenge_id:$presenceChallengeId',
    'presence_response_id:$presenceResponseId',
    'proof_created_at:$proofCreatedAt',
  ].join('\n');
}
