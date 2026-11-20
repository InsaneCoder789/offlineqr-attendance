#!/usr/bin/env python3
"""Import a reviewed Institution faculty onboarding manifest without rotating live passwords.

The manifest contains one-time passwords only while this command is running. Keep it
outside version control, restrict its permissions, and securely delete it after use.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Any

import psycopg
from psycopg.rows import dict_row

from backend.app.faculty_identity_service import hash_password
from backend.app.institution_identity import institution_email_allowed




def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Import reviewed Institution faculty identities.")
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--result", required=True, type=Path)
    parser.add_argument(
        "--rotate-existing-passwords",
        action="store_true",
        help="Explicitly replace existing faculty credentials. Avoid unless ICT has approved a reset.",
    )
    return parser.parse_args()


def validate(row: dict[str, Any], index: int) -> dict[str, str]:
    required = ("employee_code", "display_name", "designation", "org_unit", "institutional_email", "temporary_password")
    if not all(isinstance(row.get(field), str) and row[field].strip() for field in required):
        raise ValueError(f"Manifest row {index} is missing a required faculty identity field.")
    email = row["institutional_email"].strip().lower()
    if not institution_email_allowed(email):
        raise ValueError(f"Manifest row {index} does not match the configured institution email domains.")
    return {
        "employee_code": row["employee_code"].strip(),
        "display_name": " ".join(row["display_name"].split()),
        "designation": " ".join(row["designation"].split()),
        "org_unit": " ".join(row["org_unit"].split()),
        "institutional_email": email,
        "temporary_password": row["temporary_password"],
    }


def main() -> None:
    args = parse_args()
    source = json.loads(args.manifest.read_text(encoding="utf-8"))
    if not isinstance(source, list):
        raise ValueError("Manifest must be a JSON array.")
    rows = [validate(item, index + 1) for index, item in enumerate(source)]
    emails = [row["institutional_email"] for row in rows]
    codes = [row["employee_code"] for row in rows]
    if len(set(emails)) != len(emails) or len(set(codes)) != len(codes):
        raise ValueError("Manifest has duplicate official email addresses or employee codes.")

    result: list[dict[str, str]] = []
    database_url = os.environ.get("DATABASE_URL", "postgresql://localhost/offlineqr_attendance_goal02")
    with psycopg.connect(database_url, row_factory=dict_row) as conn:
        with conn.transaction():
            for row in rows:
                existing_code = conn.execute(
                    "SELECT id, institutional_email FROM faculty WHERE employee_code = %s",
                    [row["employee_code"]],
                ).fetchone()
                if existing_code and existing_code["institutional_email"].lower() != row["institutional_email"]:
                    raise ValueError(f"Employee code conflict for {row['employee_code']}.")

                faculty = conn.execute(
                    """
                    INSERT INTO faculty (employee_code, institutional_email, display_name, designation, org_unit, active)
                    VALUES (%(employee_code)s, %(institutional_email)s, %(display_name)s, %(designation)s, %(org_unit)s, true)
                    ON CONFLICT (institutional_email) DO UPDATE SET
                      employee_code = EXCLUDED.employee_code,
                      display_name = EXCLUDED.display_name,
                      designation = EXCLUDED.designation,
                      org_unit = EXCLUDED.org_unit,
                      active = true,
                      updated_at = now()
                    RETURNING id
                    """,
                    row,
                ).fetchone()
                credential = conn.execute(
                    "SELECT faculty_id FROM faculty_credentials WHERE faculty_id = %s",
                    [faculty["id"]],
                ).fetchone()
                if credential is None or args.rotate_existing_passwords:
                    conn.execute(
                        """
                        INSERT INTO faculty_credentials (faculty_id, password_hash, must_change_password)
                        VALUES (%s, %s, true)
                        ON CONFLICT (faculty_id) DO UPDATE SET
                          password_hash = EXCLUDED.password_hash,
                          must_change_password = true,
                          password_changed_at = NULL,
                          failed_login_count = 0,
                          locked_until = NULL,
                          updated_at = now()
                        """,
                        [faculty["id"], hash_password(row["temporary_password"])],
                    )
                    state = "CREATED" if credential is None else "ROTATED"
                else:
                    state = "EXISTING_CREDENTIAL_UNCHANGED"
                result.append({"institutional_email": row["institutional_email"], "state": state})

    args.result.parent.mkdir(parents=True, exist_ok=True)
    args.result.write_text(json.dumps(result, indent=2), encoding="utf-8")
    os.chmod(args.result, 0o600)
    print(json.dumps({"processed": len(result), "created_or_rotated": sum(item["state"] != "EXISTING_CREDENTIAL_UNCHANGED" for item in result)}))


if __name__ == "__main__":
    main()
