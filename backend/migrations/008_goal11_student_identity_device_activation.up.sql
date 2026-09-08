CREATE TABLE student_credentials (
    student_id uuid PRIMARY KEY REFERENCES students(id) ON DELETE CASCADE,
    password_hash text NOT NULL,
    must_change_password boolean NOT NULL DEFAULT true,
    password_changed_at timestamptz,
    failed_login_count integer NOT NULL DEFAULT 0 CHECK (failed_login_count >= 0),
    locked_until timestamptz,
    last_login_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE device_activation_tokens (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id uuid NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    replacement_request_id uuid NOT NULL UNIQUE REFERENCES device_replacement_requests(id) ON DELETE CASCADE,
    new_device_registration_id uuid NOT NULL REFERENCES device_registrations(id) ON DELETE RESTRICT,
    token_hash text NOT NULL UNIQUE,
    issued_by text NOT NULL,
    issued_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    consumed_at timestamptz,
    consumed_by_device_registration_id uuid REFERENCES device_registrations(id) ON DELETE RESTRICT,
    CHECK (expires_at > issued_at)
);

CREATE INDEX idx_student_credentials_lockout
ON student_credentials(locked_until) WHERE locked_until IS NOT NULL;

CREATE INDEX idx_device_activation_tokens_student_expiry
ON device_activation_tokens(student_id, expires_at DESC);
