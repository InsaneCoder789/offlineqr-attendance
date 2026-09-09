#!/usr/bin/env bash
set -euo pipefail

: "${DATABASE_URL:?DATABASE_URL is required}"
: "${BACKUP_ENCRYPTION_PASSPHRASE:?BACKUP_ENCRYPTION_PASSPHRASE is required}"
destination="${1:-backups}"
mkdir -p "$destination"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
output="$destination/attendance-$timestamp.dump.enc"

pg_dump --format=custom --no-owner --no-acl "$DATABASE_URL" \
  | openssl enc -aes-256-cbc -salt -pbkdf2 -iter 200000 \
      -pass env:BACKUP_ENCRYPTION_PASSPHRASE -out "$output"
shasum -a 256 "$output" > "$output.sha256"
echo "$output"
