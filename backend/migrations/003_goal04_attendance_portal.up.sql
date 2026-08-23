CREATE TYPE attendance_claim_state AS ENUM (
    'CAPTURED',
    'AWAITING_PRESENCE',
    'PROOF_READY',
    'EXPIRED',
    'REJECTED',
    'CONSUMED'
);

CREATE TABLE timetable_entries (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    course_offering_id uuid NOT NULL REFERENCES course_offerings(id) ON DELETE CASCADE,
    day_of_week integer NOT NULL CHECK (day_of_week BETWEEN 1 AND 7),
    start_time time NOT NULL,
    end_time time NOT NULL,
    room text NOT NULL,
    valid_from date NOT NULL,
    valid_until date NOT NULL,
    active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (start_time < end_time),
    CHECK (valid_from <= valid_until)
);

CREATE TABLE session_authorizations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    attendance_session_id uuid NOT NULL UNIQUE REFERENCES attendance_sessions(id) ON DELETE CASCADE,
    faculty_id uuid NOT NULL REFERENCES faculty(id) ON DELETE RESTRICT,
    course_offering_id uuid NOT NULL REFERENCES course_offerings(id) ON DELETE RESTRICT,
    key_id text NOT NULL,
    session_public_key text NOT NULL,
    session_private_key text NOT NULL,
    server_signature text NOT NULL,
    valid_from timestamptz NOT NULL,
    valid_until timestamptz NOT NULL,
    issued_at timestamptz NOT NULL DEFAULT now(),
    revoked_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (valid_from < valid_until)
);

CREATE TABLE attendance_claims (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    claim_id uuid NOT NULL UNIQUE,
    attendance_session_id uuid NOT NULL REFERENCES attendance_sessions(id) ON DELETE CASCADE,
    student_id uuid NOT NULL REFERENCES students(id) ON DELETE RESTRICT,
    device_registration_id uuid NOT NULL REFERENCES device_registrations(id) ON DELETE RESTRICT,
    qr_epoch integer NOT NULL CHECK (qr_epoch >= 0),
    qr_challenge text NOT NULL,
    qr_captured_at timestamptz NOT NULL,
    claim_created_at timestamptz NOT NULL,
    claim_expires_at timestamptz NOT NULL,
    claim_state attendance_claim_state NOT NULL DEFAULT 'AWAITING_PRESENCE',
    device_signature text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (attendance_session_id, student_id)
);

CREATE INDEX idx_timetable_entries_offering_day ON timetable_entries(course_offering_id, day_of_week);
CREATE INDEX idx_session_authorizations_faculty ON session_authorizations(faculty_id, valid_from, valid_until);
CREATE INDEX idx_attendance_claims_session_state ON attendance_claims(attendance_session_id, claim_state);
