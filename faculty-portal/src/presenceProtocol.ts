export const PRESENCE_CHALLENGE_PROTOCOL = "PRESENCE_CHALLENGE_V1";
export const PRESENCE_RESPONSE_PROTOCOL = "PRESENCE_RESPONSE_V1";
export const ATTENDANCE_PROOF_PROTOCOL = "ATTENDANCE_PROOF_V1";
export const PRESENCE_EPOCH_SECONDS = 10;
export const PRESENCE_CHALLENGE_SECONDS = 20;
export const PRIMARY_PRESENCE_TRANSPORT = "QR_ASSISTED_WEBRTC_DATA_CHANNEL";

export type PresenceChallengeFields = {
  challenge_id: string;
  session_id: string;
  claim_id: string;
  presence_epoch: number;
  nonce: string;
  issued_at: string;
  expires_at: string;
  transport: string;
  host_public_key: string;
};

export type PresenceResponseFields = {
  response_id: string;
  challenge_id: string;
  session_id: string;
  claim_id: string;
  device_registration_id: string;
  presence_epoch: number;
  responded_at: string;
  transport: string;
  challenge_nonce: string;
  host_public_key: string;
};

export type AttendanceProofFields = {
  proof_id: string;
  claim_id: string;
  session_id: string;
  student_id: string;
  device_registration_id: string;
  presence_challenge_id: string;
  presence_response_id: string;
  proof_created_at: string;
};

export function canonicalPresenceChallenge(payload: PresenceChallengeFields): string {
  return [
    PRESENCE_CHALLENGE_PROTOCOL,
    `challenge_id:${payload.challenge_id}`,
    `session_id:${payload.session_id}`,
    `claim_id:${payload.claim_id}`,
    `presence_epoch:${payload.presence_epoch}`,
    `nonce:${payload.nonce}`,
    `issued_at:${payload.issued_at}`,
    `expires_at:${payload.expires_at}`,
    `transport:${payload.transport}`,
    `host_public_key:${payload.host_public_key}`,
  ].join("\n");
}

export function canonicalPresenceResponse(payload: PresenceResponseFields): string {
  return [
    PRESENCE_RESPONSE_PROTOCOL,
    `response_id:${payload.response_id}`,
    `challenge_id:${payload.challenge_id}`,
    `session_id:${payload.session_id}`,
    `claim_id:${payload.claim_id}`,
    `device_registration_id:${payload.device_registration_id}`,
    `presence_epoch:${payload.presence_epoch}`,
    `responded_at:${payload.responded_at}`,
    `transport:${payload.transport}`,
    `challenge_nonce:${payload.challenge_nonce}`,
    `host_public_key:${payload.host_public_key}`,
  ].join("\n");
}

export function canonicalAttendanceProof(payload: AttendanceProofFields): string {
  return [
    ATTENDANCE_PROOF_PROTOCOL,
    `proof_id:${payload.proof_id}`,
    `claim_id:${payload.claim_id}`,
    `session_id:${payload.session_id}`,
    `student_id:${payload.student_id}`,
    `device_registration_id:${payload.device_registration_id}`,
    `presence_challenge_id:${payload.presence_challenge_id}`,
    `presence_response_id:${payload.presence_response_id}`,
    `proof_created_at:${payload.proof_created_at}`,
  ].join("\n");
}
