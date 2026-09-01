ALTER TABLE device_registrations
ADD COLUMN manufacturer text,
ADD COLUMN device_model text,
ADD COLUMN os_version text,
ADD COLUMN os_api_level integer,
ADD COLUMN is_physical_device boolean,
ADD COLUMN integrity_status text NOT NULL DEFAULT 'UNVERIFIED',
ADD COLUMN integrity_checked_at timestamptz,
ADD COLUMN risk_flags jsonb NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE device_registrations
ADD CONSTRAINT chk_device_integrity_status
CHECK (integrity_status IN ('UNVERIFIED', 'DECLARED_PHYSICAL', 'VERIFIED', 'REVIEW_REQUIRED', 'REJECTED'));

ALTER TABLE device_replacement_requests
ADD COLUMN decision_note text,
ADD COLUMN decided_by text,
ADD COLUMN decided_at timestamptz;

CREATE INDEX idx_device_registrations_integrity
ON device_registrations(integrity_status, status, last_seen_at DESC);

CREATE INDEX idx_audit_logs_device_history
ON audit_logs(entity_type, entity_id, occurred_at DESC);
