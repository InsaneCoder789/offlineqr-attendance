#!/usr/bin/env bash
set -euo pipefail

DB_NAME="${DB_NAME:-kiit_attendance_goal02}"

dropdb --if-exists "$DB_NAME"
createdb "$DB_NAME"
psql -v ON_ERROR_STOP=1 -d "$DB_NAME" -f backend/migrations/001_goal02_academic_foundation.up.sql
psql -v ON_ERROR_STOP=1 -d "$DB_NAME" -f backend/migrations/002_goal03_device_security.up.sql
psql -v ON_ERROR_STOP=1 -d "$DB_NAME" -f backend/migrations/003_goal04_attendance_portal.up.sql
psql -v ON_ERROR_STOP=1 -d "$DB_NAME" -f backend/migrations/004_goal06_presence_protocol.up.sql
psql -v ON_ERROR_STOP=1 -d "$DB_NAME" -f backend/migrations/005_goal08_security_hardening.up.sql
psql -v ON_ERROR_STOP=1 -d "$DB_NAME" -f backend/migrations/006_goal09_admin_device_governance.up.sql
psql -v ON_ERROR_STOP=1 -d "$DB_NAME" -f backend/seeds/goal02_dev_seed.sql
