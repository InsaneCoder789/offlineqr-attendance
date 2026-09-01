-- Preserve the evidence that a client actually scanned an institution-signed QR.
-- The reconciliation window is technical state; it does not create a third
-- academic attendance status.
ALTER TYPE attendance_session_state ADD VALUE IF NOT EXISTS 'SYNCING';
ALTER TYPE attendance_session_state ADD VALUE IF NOT EXISTS 'RECONCILED';

ALTER TABLE attendance_sessions
  ADD COLUMN IF NOT EXISTS reconcile_until timestamptz,
  ADD COLUMN IF NOT EXISTS reconciliation_state text NOT NULL DEFAULT 'NOT_REQUIRED'
    CHECK (reconciliation_state IN ('NOT_REQUIRED', 'PENDING', 'RECONCILED'));

ALTER TABLE attendance_claims
  ADD COLUMN IF NOT EXISTS qr_issued_at timestamptz,
  ADD COLUMN IF NOT EXISTS qr_expires_at timestamptz,
  ADD COLUMN IF NOT EXISTS qr_signature text;

CREATE INDEX IF NOT EXISTS idx_attendance_sessions_reconciliation
  ON attendance_sessions(state, reconcile_until)
  WHERE state = 'SYNCING';

CREATE INDEX IF NOT EXISTS idx_attendance_claims_session_capture
  ON attendance_claims(attendance_session_id, qr_captured_at);
