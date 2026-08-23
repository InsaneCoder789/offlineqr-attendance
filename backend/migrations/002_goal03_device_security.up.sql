CREATE TYPE device_registration_status AS ENUM ('PENDING', 'ACTIVE', 'REVOKED');
CREATE TYPE device_challenge_purpose AS ENUM ('ENROLLMENT', 'VERIFICATION', 'REPLACEMENT');
CREATE TYPE device_replacement_status AS ENUM ('PENDING', 'APPROVED', 'REJECTED', 'CANCELLED');
CREATE TYPE device_key_protection AS ENUM ('SOFTWARE_PROTECTED', 'PLATFORM_STORED', 'HARDWARE_BACKED_UNVERIFIED');

CREATE TABLE auth_identities (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id uuid REFERENCES students(id) ON DELETE CASCADE,
    faculty_id uuid REFERENCES faculty(id) ON DELETE CASCADE,
    issuer text NOT NULL,
    subject text NOT NULL,
    institutional_email text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (
        (student_id IS NOT NULL AND faculty_id IS NULL)
        OR (student_id IS NULL AND faculty_id IS NOT NULL)
    ),
    UNIQUE (issuer, subject)
);

CREATE TABLE audit_logs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_type text NOT NULL,
    actor_id uuid,
    event_type text NOT NULL,
    entity_type text NOT NULL,
    entity_id uuid,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    correlation_id text NOT NULL DEFAULT 'development',
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE device_registrations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id uuid NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    public_key text NOT NULL,
    public_key_algorithm text NOT NULL,
    key_fingerprint text NOT NULL,
    platform text NOT NULL,
    display_label text,
    app_instance_metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    key_protection device_key_protection NOT NULL DEFAULT 'SOFTWARE_PROTECTED',
    status device_registration_status NOT NULL DEFAULT 'PENDING',
    registered_at timestamptz,
    revoked_at timestamptz,
    last_seen_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (public_key_algorithm = 'Ed25519'),
    CHECK (key_fingerprint ~ '^[0-9a-f]{64}$'),
    UNIQUE (key_fingerprint)
);

CREATE UNIQUE INDEX unique_active_device_per_student
ON device_registrations(student_id)
WHERE status = 'ACTIVE';

CREATE TABLE device_challenges (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id uuid NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    device_registration_id uuid REFERENCES device_registrations(id) ON DELETE CASCADE,
    purpose device_challenge_purpose NOT NULL,
    challenge text NOT NULL,
    issued_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    used_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (expires_at > issued_at),
    UNIQUE (challenge)
);

CREATE TABLE device_replacement_requests (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id uuid NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    old_device_registration_id uuid NOT NULL REFERENCES device_registrations(id) ON DELETE RESTRICT,
    new_device_registration_id uuid NOT NULL REFERENCES device_registrations(id) ON DELETE RESTRICT,
    reason text NOT NULL,
    status device_replacement_status NOT NULL DEFAULT 'PENDING',
    requested_at timestamptz NOT NULL DEFAULT now(),
    approved_at timestamptz,
    approved_by text,
    rejected_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX unique_pending_replacement_per_student
ON device_replacement_requests(student_id)
WHERE status = 'PENDING';

ALTER TABLE attendance_records
ADD CONSTRAINT fk_attendance_records_device_registration
FOREIGN KEY (device_registration_id)
REFERENCES device_registrations(id)
ON DELETE RESTRICT;

CREATE INDEX idx_device_registrations_student_status
ON device_registrations(student_id, status);

CREATE INDEX idx_device_challenges_student_purpose
ON device_challenges(student_id, purpose, issued_at DESC);

CREATE INDEX idx_device_replacement_student_status
ON device_replacement_requests(student_id, status);

CREATE INDEX idx_audit_logs_event_time
ON audit_logs(event_type, occurred_at DESC);
