import { ed25519 } from "@noble/curves/ed25519";

export const ATTENDANCE_QR_PROTOCOL = "ATTENDANCE_QR_V1";
export const QR_EPOCH_SECONDS = 5;

export type SessionAuthorization = {
  authorization_id: string;
  protocol_version: string;
  session_id: string;
  course_offering_id: string;
  faculty_id: string;
  valid_from: string;
  valid_until: string;
  key_id: string;
  session_public_key: string;
  session_private_key?: string;
  server_signature: string;
};

export type QrPayload = {
  protocol_version: string;
  session_id: string;
  epoch: number;
  issued_at: string;
  expires_at: string;
  challenge: string;
  key_id: string;
  signature: string;
  session_authorization: SessionAuthorization;
};

export function epochFor(now: Date, origin: Date): number {
  return Math.max(0, Math.floor((now.getTime() - origin.getTime()) / 1000 / QR_EPOCH_SECONDS));
}

export function epochWindow(origin: Date, epoch: number): { issuedAt: Date; expiresAt: Date } {
  const issuedAt = new Date(origin.getTime() + epoch * QR_EPOCH_SECONDS * 1000);
  return { issuedAt, expiresAt: new Date(issuedAt.getTime() + QR_EPOCH_SECONDS * 1000) };
}

export function canonicalAttendanceQr(payload: Omit<QrPayload, "protocol_version" | "signature" | "session_authorization">): string {
  return [
    ATTENDANCE_QR_PROTOCOL,
    `session_id:${payload.session_id}`,
    `epoch:${payload.epoch}`,
    `issued_at:${payload.issued_at}`,
    `expires_at:${payload.expires_at}`,
    `challenge:${payload.challenge}`,
    `key_id:${payload.key_id}`,
  ].join("\n");
}

export async function createQrPayload(authorization: SessionAuthorization, origin: string, now = new Date()): Promise<QrPayload> {
  if (!authorization.session_private_key) {
    throw new Error("offline session credential is unavailable");
  }
  const epoch = epochFor(now, new Date(origin));
  const window = epochWindow(new Date(origin), epoch);
  const unsigned = {
    session_id: authorization.session_id,
    epoch,
    issued_at: window.issuedAt.toISOString(),
    expires_at: window.expiresAt.toISOString(),
    challenge: challengeFor(authorization.session_id, epoch, authorization.session_public_key),
    key_id: authorization.key_id,
  };
  const signature = ed25519.sign(
    new TextEncoder().encode(canonicalAttendanceQr(unsigned)),
    base64UrlDecode(authorization.session_private_key),
  );
  const publicAuthorization = { ...authorization };
  delete publicAuthorization.session_private_key;
  return {
    protocol_version: ATTENDANCE_QR_PROTOCOL,
    ...unsigned,
    signature: base64UrlEncode(signature),
    session_authorization: publicAuthorization,
  };
}

export function secondsUntilNextEpoch(now: Date, origin: Date): number {
  const elapsed = Math.max(0, Math.floor((now.getTime() - origin.getTime()) / 1000));
  return QR_EPOCH_SECONDS - (elapsed % QR_EPOCH_SECONDS);
}

export function challengeFor(sessionId: string, epoch: number, sessionPublicKey: string): string {
  return base64UrlEncode(new TextEncoder().encode(`${sessionId}:${epoch}:${sessionPublicKey}`)).slice(0, 43);
}

export function base64UrlEncode(bytes: Uint8Array): string {
  const binary = String.fromCharCode(...bytes);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

export function base64UrlDecode(value: string): Uint8Array {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(value.length / 4) * 4, "=");
  return Uint8Array.from(atob(padded), (char) => char.charCodeAt(0));
}
