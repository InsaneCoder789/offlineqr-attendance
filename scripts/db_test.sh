#!/usr/bin/env bash
set -euo pipefail

DB_NAME="${DB_NAME:-kiit_attendance_goal02}"

psql -v ON_ERROR_STOP=1 -d "$DB_NAME" -f backend/tests/goal02_database_checks.sql

