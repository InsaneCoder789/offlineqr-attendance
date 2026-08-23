CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TYPE attendance_status AS ENUM ('PRESENT', 'ABSENT');
CREATE TYPE attendance_method AS ENUM ('DYNAMIC_QR', 'FACULTY_ATTESTATION');
CREATE TYPE attendance_session_state AS ENUM ('CREATED', 'ACTIVE', 'CLOSED', 'CANCELLED');
CREATE TYPE sync_state AS ENUM ('SERVER_VERIFIED', 'PENDING_SYNC', 'REQUIRES_REVIEW');
CREATE TYPE academic_term_status AS ENUM ('PLANNED', 'ACTIVE', 'CLOSED');

CREATE TABLE academic_terms (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    academic_year text NOT NULL,
    term_number integer NOT NULL CHECK (term_number > 0),
    starts_on date NOT NULL,
    ends_on date NOT NULL,
    status academic_term_status NOT NULL DEFAULT 'PLANNED',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (starts_on <= ends_on),
    UNIQUE (academic_year, term_number)
);

CREATE TABLE students (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    roll_number text NOT NULL,
    institutional_email text NOT NULL,
    display_name text NOT NULL,
    active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (roll_number),
    UNIQUE (institutional_email)
);

CREATE TABLE faculty (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    employee_code text,
    institutional_email text NOT NULL,
    display_name text NOT NULL,
    active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (employee_code),
    UNIQUE (institutional_email)
);

CREATE TABLE sections (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    academic_term_id uuid NOT NULL REFERENCES academic_terms(id) ON DELETE RESTRICT,
    code text NOT NULL,
    active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (academic_term_id, code)
);

CREATE TABLE courses (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code text NOT NULL,
    name text NOT NULL,
    active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (code)
);

CREATE TABLE course_offerings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id uuid NOT NULL REFERENCES courses(id) ON DELETE RESTRICT,
    academic_term_id uuid NOT NULL REFERENCES academic_terms(id) ON DELETE RESTRICT,
    section_id uuid NOT NULL REFERENCES sections(id) ON DELETE RESTRICT,
    active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (course_id, academic_term_id, section_id)
);

CREATE TABLE faculty_assignments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    faculty_id uuid NOT NULL REFERENCES faculty(id) ON DELETE RESTRICT,
    course_offering_id uuid NOT NULL REFERENCES course_offerings(id) ON DELETE RESTRICT,
    role text NOT NULL DEFAULT 'PRIMARY',
    starts_at timestamptz,
    ends_at timestamptz,
    active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (starts_at IS NULL OR ends_at IS NULL OR starts_at <= ends_at),
    UNIQUE (faculty_id, course_offering_id, role)
);

CREATE TABLE enrollments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id uuid NOT NULL REFERENCES students(id) ON DELETE RESTRICT,
    course_offering_id uuid NOT NULL REFERENCES course_offerings(id) ON DELETE RESTRICT,
    active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (student_id, course_offering_id)
);

CREATE TABLE attendance_sessions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    course_offering_id uuid NOT NULL REFERENCES course_offerings(id) ON DELETE RESTRICT,
    created_by_faculty_id uuid NOT NULL REFERENCES faculty(id) ON DELETE RESTRICT,
    scheduled_start timestamptz NOT NULL,
    scheduled_end timestamptz NOT NULL,
    started_at timestamptz,
    closed_at timestamptz,
    state attendance_session_state NOT NULL DEFAULT 'CREATED',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (scheduled_start < scheduled_end),
    CHECK (started_at IS NULL OR closed_at IS NULL OR started_at <= closed_at)
);

CREATE TABLE attendance_session_roster (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    attendance_session_id uuid NOT NULL REFERENCES attendance_sessions(id) ON DELETE CASCADE,
    enrollment_id uuid NOT NULL REFERENCES enrollments(id) ON DELETE RESTRICT,
    student_id uuid NOT NULL REFERENCES students(id) ON DELETE RESTRICT,
    course_offering_id uuid NOT NULL REFERENCES course_offerings(id) ON DELETE RESTRICT,
    roll_number_snapshot text NOT NULL,
    student_name_snapshot text NOT NULL,
    section_code_snapshot text NOT NULL,
    course_code_snapshot text NOT NULL,
    course_name_snapshot text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (attendance_session_id, student_id),
    UNIQUE (attendance_session_id, enrollment_id)
);

CREATE TABLE attendance_records (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    attendance_session_id uuid NOT NULL REFERENCES attendance_sessions(id) ON DELETE CASCADE,
    student_id uuid NOT NULL REFERENCES students(id) ON DELETE RESTRICT,
    device_registration_id uuid,
    status attendance_status NOT NULL,
    method attendance_method,
    technical_state sync_state NOT NULL DEFAULT 'SERVER_VERIFIED',
    recorded_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (
        (status = 'PRESENT' AND method IS NOT NULL)
        OR (status = 'ABSENT' AND method IS NULL)
    ),
    UNIQUE (attendance_session_id, student_id)
);

CREATE TABLE faculty_attestations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    attendance_record_id uuid NOT NULL UNIQUE REFERENCES attendance_records(id) ON DELETE CASCADE,
    attendance_session_id uuid NOT NULL REFERENCES attendance_sessions(id) ON DELETE CASCADE,
    student_id uuid NOT NULL REFERENCES students(id) ON DELETE RESTRICT,
    faculty_id uuid NOT NULL REFERENCES faculty(id) ON DELETE RESTRICT,
    reason text NOT NULL,
    attested_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE sync_cursors (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id uuid NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    cursor_token text NOT NULL,
    server_generated_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (student_id, cursor_token)
);

CREATE INDEX idx_sections_term ON sections(academic_term_id);
CREATE INDEX idx_course_offerings_term_section ON course_offerings(academic_term_id, section_id);
CREATE INDEX idx_enrollments_student ON enrollments(student_id);
CREATE INDEX idx_enrollments_offering ON enrollments(course_offering_id);
CREATE INDEX idx_faculty_assignments_offering ON faculty_assignments(course_offering_id);
CREATE INDEX idx_attendance_sessions_offering_time ON attendance_sessions(course_offering_id, scheduled_start);
CREATE INDEX idx_attendance_records_student_session ON attendance_records(student_id, attendance_session_id);
CREATE INDEX idx_attendance_records_session_status ON attendance_records(attendance_session_id, status);
CREATE INDEX idx_roster_student_session ON attendance_session_roster(student_id, attendance_session_id);

