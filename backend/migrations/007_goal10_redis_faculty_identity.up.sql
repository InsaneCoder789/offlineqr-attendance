ALTER TABLE faculty
  ADD COLUMN IF NOT EXISTS phone_number text,
  ADD COLUMN IF NOT EXISTS designation text,
  ADD COLUMN IF NOT EXISTS org_unit text,
  ADD COLUMN IF NOT EXISTS access_role text NOT NULL DEFAULT 'FACULTY'
    CHECK (access_role IN ('FACULTY', 'ICT_ADMIN', 'ACADEMIC_ADMIN')),
  ADD COLUMN IF NOT EXISTS profile_updated_at timestamptz NOT NULL DEFAULT now();

CREATE TABLE faculty_credentials (
    faculty_id uuid PRIMARY KEY REFERENCES faculty(id) ON DELETE CASCADE,
    password_hash text NOT NULL,
    must_change_password boolean NOT NULL DEFAULT true,
    password_changed_at timestamptz,
    failed_login_count integer NOT NULL DEFAULT 0 CHECK (failed_login_count >= 0),
    locked_until timestamptz,
    last_login_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS unique_live_attendance_session_per_offering_time
ON attendance_sessions(course_offering_id, scheduled_start)
WHERE state IN ('CREATED', 'ACTIVE', 'SYNCING');

CREATE INDEX IF NOT EXISTS idx_faculty_credentials_lockout
ON faculty_credentials(locked_until)
WHERE locked_until IS NOT NULL;
