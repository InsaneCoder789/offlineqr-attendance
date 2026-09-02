DROP INDEX IF EXISTS idx_faculty_credentials_lockout;
DROP INDEX IF EXISTS unique_live_attendance_session_per_offering_time;
DROP TABLE IF EXISTS faculty_credentials;
ALTER TABLE faculty
  DROP COLUMN IF EXISTS profile_updated_at,
  DROP COLUMN IF EXISTS org_unit,
  DROP COLUMN IF EXISTS access_role,
  DROP COLUMN IF EXISTS designation,
  DROP COLUMN IF EXISTS phone_number;
