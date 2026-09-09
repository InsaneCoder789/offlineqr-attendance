#!/usr/bin/env bash
set -euo pipefail

: "${DATABASE_URL:?DATABASE_URL is required}"
: "${BACKUP_ENCRYPTION_PASSPHRASE:?BACKUP_ENCRYPTION_PASSPHRASE is required}"
backup="${1:?encrypted backup path is required}"

shasum -a 256 --check "$backup.sha256"
temporary="$(mktemp)"
trap 'rm -f "$temporary"' EXIT
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
  -pass env:BACKUP_ENCRYPTION_PASSPHRASE -in "$backup" -out "$temporary"
pg_restore --clean --if-exists --no-owner --no-acl --dbname "$DATABASE_URL" "$temporary"
