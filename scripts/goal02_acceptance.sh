#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_PATH="$(mktemp -t institution_goal02_offline.XXXXXX.sqlite)"
PORT="${PORT:-8000}"

cd "$ROOT_DIR"
./scripts/db_reset.sh

PYTHONPATH=. .venv/bin/uvicorn backend.app.main:app --host 127.0.0.1 --port "$PORT" >/tmp/institution_goal02_uvicorn.log 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true; rm -f "$DB_PATH"' EXIT

for _ in {1..30}; do
  if curl -fsS "http://127.0.0.1:$PORT/api/v1/health" >/dev/null; then
    break
  fi
  sleep 0.5
done

curl -fsS "http://127.0.0.1:$PORT/api/v1/health" >/dev/null

cd "$ROOT_DIR/client"
GOAL02_DB_PATH="$DB_PATH" \
GOAL02_MODE=sync \
GOAL02_BACKEND_URL="http://127.0.0.1:$PORT" \
flutter test test/core/live_backend_acceptance_test.dart

kill "$SERVER_PID"
wait "$SERVER_PID" 2>/dev/null || true
trap 'rm -f "$DB_PATH"' EXIT

GOAL02_DB_PATH="$DB_PATH" \
GOAL02_MODE=offline \
flutter test test/core/live_backend_acceptance_test.dart

