#!/usr/bin/env bash
set -euo pipefail

TEST_DB_NAME="${TEST_DB_NAME:-offlineqr_attendance_test}"
TEST_DATABASE_URL="${TEST_DATABASE_URL:-postgresql://localhost/${TEST_DB_NAME}}"

cleanup() {
  dropdb --if-exists "${TEST_DB_NAME}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

DB_NAME="${TEST_DB_NAME}" scripts/db_reset.sh >/dev/null
APP_ENV=development DATABASE_URL="${TEST_DATABASE_URL}" PYTHONPATH=. \
  .venv/bin/python -m unittest discover -s backend/tests -p 'test_*.py'
