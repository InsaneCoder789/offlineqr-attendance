from __future__ import annotations

from typing import Any
from uuid import UUID

import psycopg
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

from .config import get_settings
from .db import connect
from .errors import ApiError


def admin_device_stats() -> dict[str, int]:
    with _connect() as conn:
        row = conn.execute(
            """
            SELECT
              COUNT(*)::int AS total_devices,
              COUNT(*) FILTER (WHERE status = 'ACTIVE')::int AS active_devices,
              COUNT(*) FILTER (WHERE status = 'REVOKED')::int AS revoked_devices,
              COUNT(*) FILTER (WHERE integrity_status IN ('REVIEW_REQUIRED', 'REJECTED'))::int AS review_required,
              (SELECT COUNT(*)::int FROM device_replacement_requests WHERE status IN ('PENDING', 'APPROVED')) AS pending_replacements
            FROM device_registrations
            """
        ).fetchone()
        return dict(row)


def admin_devices(*, query: str | None, status: str | None, limit: int = 120) -> list[dict[str, Any]]:
    normalized_query = (query or "").strip()
    normalized_status = (status or "").strip().upper()
    if normalized_status and normalized_status not in {"ACTIVE", "PENDING", "REVOKED"}:
        raise ApiError("INVALID_DEVICE_STATUS", "Use ACTIVE, PENDING, or REVOKED.", 400)
    bounded_limit = max(1, min(limit, 250))
    with _connect() as conn:
        rows = conn.execute(
            """
            SELECT d.id, d.student_id, s.roll_number, s.display_name AS student_name,
                   COALESCE(section_snapshot.code, 'Unassigned') AS section_code,
                   d.status::text AS status, d.platform, d.manufacturer, d.device_model,
                   d.os_version, d.is_physical_device, d.integrity_status, d.risk_flags,
                   d.display_label, d.registered_at, d.last_seen_at,
                   replacement.id AS pending_replacement_id
            FROM device_registrations d
            JOIN students s ON s.id = d.student_id
            LEFT JOIN LATERAL (
                SELECT sec.code
                FROM enrollments e
                JOIN course_offerings co ON co.id = e.course_offering_id
                JOIN sections sec ON sec.id = co.section_id
                WHERE e.student_id = s.id AND e.active = true
                ORDER BY e.created_at ASC
                LIMIT 1
            ) AS section_snapshot ON true
            LEFT JOIN device_replacement_requests replacement
              ON replacement.new_device_registration_id = d.id AND replacement.status = 'PENDING'
            WHERE (%s = '' OR s.roll_number ILIKE %s OR s.display_name ILIKE %s OR d.key_fingerprint ILIKE %s)
              AND (%s = '' OR d.status::text = %s)
            ORDER BY CASE d.status WHEN 'PENDING' THEN 0 WHEN 'ACTIVE' THEN 1 ELSE 2 END,
                     d.last_seen_at DESC NULLS LAST, d.created_at DESC
            LIMIT %s
            """,
            [
                normalized_query,
                f"%{normalized_query}%",
                f"%{normalized_query}%",
                f"%{normalized_query}%",
                normalized_status,
                normalized_status,
                bounded_limit,
            ],
        ).fetchall()
        return [_public_device(row) for row in rows]


def admin_device_detail(device_registration_id: UUID) -> dict[str, Any]:
    with _connect() as conn:
        row = conn.execute(
            """
            SELECT d.id, d.student_id, s.roll_number, s.display_name AS student_name,
                   COALESCE(section_snapshot.code, 'Unassigned') AS section_code,
                   d.status::text AS status, d.platform, d.manufacturer, d.device_model,
                   d.os_version, d.os_api_level, d.is_physical_device, d.integrity_status,
                   d.risk_flags, d.display_label, d.registered_at, d.revoked_at, d.last_seen_at,
                   d.key_fingerprint, d.app_instance_metadata,
                   replacement.id AS pending_replacement_id
            FROM device_registrations d
            JOIN students s ON s.id = d.student_id
            LEFT JOIN LATERAL (
                SELECT sec.code
                FROM enrollments e
                JOIN course_offerings co ON co.id = e.course_offering_id
                JOIN sections sec ON sec.id = co.section_id
                WHERE e.student_id = s.id AND e.active = true
                ORDER BY e.created_at ASC
                LIMIT 1
            ) AS section_snapshot ON true
            LEFT JOIN device_replacement_requests replacement
              ON replacement.new_device_registration_id = d.id AND replacement.status = 'PENDING'
            WHERE d.id = %s
            """,
            [device_registration_id],
        ).fetchone()
        if row is None:
            raise ApiError("DEVICE_NOT_FOUND", "Device registration was not found.", 404)
        result = _public_device(row)
        result.update(
            {
                "key_fingerprint": row["key_fingerprint"],
                "revoked_at": row["revoked_at"],
                "app_instance_metadata": row["app_instance_metadata"] or {},
            }
        )
        return result


def admin_device_history(device_registration_id: UUID) -> list[dict[str, Any]]:
    with _connect() as conn:
        rows = conn.execute(
            """
            SELECT id, event_type, actor_type, occurred_at, correlation_id, metadata
            FROM audit_logs
            WHERE (entity_type = 'device_registration' AND entity_id = %s)
               OR (entity_type = 'device_replacement_request' AND entity_id IN (
                    SELECT id FROM device_replacement_requests
                    WHERE old_device_registration_id = %s OR new_device_registration_id = %s
               ))
            ORDER BY occurred_at DESC
            LIMIT 200
            """,
            [device_registration_id, device_registration_id, device_registration_id],
        ).fetchall()
        return [dict(row) for row in rows]


def admin_pending_replacements() -> list[dict[str, Any]]:
    with _connect() as conn:
        rows = conn.execute(
            """
            SELECT r.id, r.student_id, s.roll_number, s.display_name AS student_name,
                   r.old_device_registration_id, r.new_device_registration_id,
                   r.reason, r.status::text AS status, r.requested_at,
                   old_device.platform AS old_platform, old_device.manufacturer AS old_manufacturer,
                   old_device.device_model AS old_model,
                   new_device.platform AS new_platform, new_device.manufacturer AS new_manufacturer,
                   new_device.device_model AS new_model, new_device.integrity_status AS new_integrity_status,
                   new_device.risk_flags AS new_risk_flags
            FROM device_replacement_requests r
            JOIN students s ON s.id = r.student_id
            JOIN device_registrations old_device ON old_device.id = r.old_device_registration_id
            JOIN device_registrations new_device ON new_device.id = r.new_device_registration_id
            WHERE r.status IN ('PENDING', 'APPROVED')
            ORDER BY r.requested_at ASC
            """
        ).fetchall()
        return [dict(row) for row in rows]


def _public_device(row: dict[str, Any]) -> dict[str, Any]:
    result = dict(row)
    fingerprint = result.pop("key_fingerprint", None)
    result["device_reference"] = f"DEV-{(fingerprint or str(result['id']).replace('-', '')[:12]).upper()}"
    result["risk_flags"] = result.get("risk_flags") or []
    return result


def _connect() -> psycopg.Connection:
    return connect()
