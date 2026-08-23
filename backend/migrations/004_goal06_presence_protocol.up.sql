ALTER TYPE attendance_method ADD VALUE IF NOT EXISTS 'SECURE_PROOF';

CREATE TYPE presence_transport AS ENUM (
    'QR_ASSISTED_WEBRTC_DATA_CHANNEL',
    'LOCAL_NETWORK',
    'WEBRTC',
    'BLUETOOTH',
    'FALLBACK_UNAVAILABLE'
);

CREATE TYPE presence_verification_state AS ENUM (
    'ISSUED',
    'RESPONDED',
    'VERIFIED',
    'REJECTED',
    'EXPIRED'
);

CREATE TABLE presence_challenges (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    challenge_id uuid NOT NULL UNIQUE,
    attendance_session_id uuid NOT NULL REFERENCES attendance_sessions(id) ON DELETE CASCADE,
    attendance_claim_id uuid NOT NULL REFERENCES attendance_claims(claim_id) ON DELETE CASCADE,
    presence_epoch integer NOT NULL CHECK (presence_epoch >= 0),
    nonce text NOT NULL,
    issued_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL,
    transport presence_transport NOT NULL,
    host_public_key text NOT NULL,
    state presence_verification_state NOT NULL DEFAULT 'ISSUED',
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (issued_at < expires_at),
    UNIQUE (attendance_claim_id, presence_epoch, nonce)
);

CREATE TABLE presence_responses (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    response_id uuid NOT NULL UNIQUE,
    challenge_id uuid NOT NULL REFERENCES presence_challenges(challenge_id) ON DELETE CASCADE,
    attendance_session_id uuid NOT NULL REFERENCES attendance_sessions(id) ON DELETE CASCADE,
    attendance_claim_id uuid NOT NULL REFERENCES attendance_claims(claim_id) ON DELETE CASCADE,
    device_registration_id uuid NOT NULL REFERENCES device_registrations(id) ON DELETE RESTRICT,
    presence_epoch integer NOT NULL CHECK (presence_epoch >= 0),
    responded_at timestamptz NOT NULL,
    transport presence_transport NOT NULL,
    challenge_nonce text NOT NULL,
    host_public_key text NOT NULL,
    device_signature text NOT NULL,
    state presence_verification_state NOT NULL DEFAULT 'RESPONDED',
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (challenge_id, device_registration_id),
    UNIQUE (attendance_claim_id, device_registration_id)
);

CREATE TABLE attendance_proofs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    proof_id uuid NOT NULL UNIQUE,
    attendance_claim_id uuid NOT NULL UNIQUE REFERENCES attendance_claims(claim_id) ON DELETE CASCADE,
    attendance_session_id uuid NOT NULL REFERENCES attendance_sessions(id) ON DELETE CASCADE,
    student_id uuid NOT NULL REFERENCES students(id) ON DELETE RESTRICT,
    device_registration_id uuid NOT NULL REFERENCES device_registrations(id) ON DELETE RESTRICT,
    presence_challenge_id uuid NOT NULL REFERENCES presence_challenges(challenge_id) ON DELETE RESTRICT,
    presence_response_id uuid NOT NULL REFERENCES presence_responses(response_id) ON DELETE RESTRICT,
    proof_created_at timestamptz NOT NULL,
    final_device_signature text NOT NULL,
    sync_state sync_state NOT NULL DEFAULT 'PENDING_SYNC',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (attendance_session_id, student_id),
    UNIQUE (attendance_session_id, device_registration_id)
);

CREATE INDEX idx_presence_challenges_session_epoch ON presence_challenges(attendance_session_id, presence_epoch);
CREATE INDEX idx_presence_responses_claim_state ON presence_responses(attendance_claim_id, state);
CREATE INDEX idx_attendance_proofs_sync_state ON attendance_proofs(sync_state, created_at);
