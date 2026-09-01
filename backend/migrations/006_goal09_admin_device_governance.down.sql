DROP INDEX IF EXISTS idx_audit_logs_device_history;
DROP INDEX IF EXISTS idx_device_registrations_integrity;

ALTER TABLE device_replacement_requests
DROP COLUMN IF EXISTS decided_at,
DROP COLUMN IF EXISTS decided_by,
DROP COLUMN IF EXISTS decision_note;

ALTER TABLE device_registrations
DROP CONSTRAINT IF EXISTS chk_device_integrity_status;

ALTER TABLE device_registrations
DROP COLUMN IF EXISTS risk_flags,
DROP COLUMN IF EXISTS integrity_checked_at,
DROP COLUMN IF EXISTS integrity_status,
DROP COLUMN IF EXISTS is_physical_device,
DROP COLUMN IF EXISTS os_api_level,
DROP COLUMN IF EXISTS os_version,
DROP COLUMN IF EXISTS device_model,
DROP COLUMN IF EXISTS manufacturer;
