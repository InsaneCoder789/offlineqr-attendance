DROP INDEX IF EXISTS idx_attendance_claims_session_capture;
DROP INDEX IF EXISTS idx_attendance_sessions_reconciliation;
ALTER TABLE attendance_claims
  DROP COLUMN IF EXISTS qr_signature,
  DROP COLUMN IF EXISTS qr_expires_at,
  DROP COLUMN IF EXISTS qr_issued_at;
ALTER TABLE attendance_sessions
  DROP COLUMN IF EXISTS reconciliation_state,
  DROP COLUMN IF EXISTS reconcile_until;
