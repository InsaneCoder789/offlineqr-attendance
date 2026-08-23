ALTER TABLE attendance_records
DROP CONSTRAINT IF EXISTS fk_attendance_records_device_registration;

DROP TABLE IF EXISTS device_replacement_requests;
DROP TABLE IF EXISTS device_challenges;
DROP INDEX IF EXISTS unique_active_device_per_student;
DROP TABLE IF EXISTS device_registrations;
DROP TABLE IF EXISTS audit_logs;
DROP TABLE IF EXISTS auth_identities;

DROP TYPE IF EXISTS device_key_protection;
DROP TYPE IF EXISTS device_replacement_status;
DROP TYPE IF EXISTS device_challenge_purpose;
DROP TYPE IF EXISTS device_registration_status;
