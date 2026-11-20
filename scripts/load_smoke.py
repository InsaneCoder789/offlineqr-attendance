from __future__ import annotations

import argparse
import concurrent.futures
import json
import threading
import time
import urllib.error
import urllib.request
from uuid import UUID, uuid4


def request(url: str) -> float:
    started = time.perf_counter()
    with urllib.request.urlopen(url, timeout=5) as response:
        if response.status != 200 or json.load(response).get("status") != "ready":
            raise RuntimeError("readiness response was invalid")
    return time.perf_counter() - started


def _percentile(sorted_values: list[float], fraction: float) -> float:
    if not sorted_values:
        return 0.0
    index = min(len(sorted_values) - 1, max(0, int(round(fraction * len(sorted_values))) - 1))
    return round(sorted_values[index] * 1000, 1)


def readiness_main(args: argparse.Namespace) -> None:
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        durations = list(pool.map(request, [args.url] * args.requests))
    durations.sort()
    p95 = durations[int(len(durations) * 0.95) - 1]
    print(json.dumps({"requests": len(durations), "p95_ms": round(p95 * 1000, 2)}))
    if p95 > 1.0:
        raise SystemExit("p95 exceeded 1000 ms")


# --------------------------------------------------------------------------------------
# class-start scenario: login -> bootstrap sync -> proof batch, at a fixed arrival rate.
# Needs DATABASE_URL (same scratch DB the target server uses) and PYTHONPATH=. so it can
# prepare fixtures (students, passwords, devices, an ACTIVE session, signed proofs).
# Run the server with TRUSTED_PROXY_HOPS=1 so each simulated student gets its own
# X-Forwarded-For address; otherwise the per-IP limiter (correctly) throttles one client.
# --------------------------------------------------------------------------------------
PASSWORD = "LoadSmoke#2026pw"


def _prepare_class_start(students: int, roll_base: int) -> dict:
    import psycopg
    from argon2 import PasswordHasher
    from nacl.signing import SigningKey

    from backend.app.attendance_protocol import canonical_attendance_claim
    from backend.app.attendance_service import qr_payload_for, start_attendance_session
    from backend.app.config import get_settings
    from backend.app.device_crypto import b64url_encode, public_key_fingerprint
    from backend.app.institution_clock import institution_today
    from backend.app.presence_protocol import (
        ATTENDANCE_PROOF_PROTOCOL,
        canonical_attendance_proof,
        canonical_presence_response,
    )
    from datetime import timedelta

    password_hash = PasswordHasher(time_cost=3, memory_cost=65536, parallelism=2).hash(PASSWORD)
    with psycopg.connect(get_settings().database_url) as conn:
        faculty_id, offering_id = conn.execute(
            """
            SELECT fa.faculty_id, te.course_offering_id
            FROM timetable_entries te
            JOIN faculty_assignments fa ON fa.course_offering_id = te.course_offering_id AND fa.active
            WHERE te.day_of_week = %s AND te.active
            ORDER BY te.start_time LIMIT 1
            """,
            [institution_today().isoweekday()],
        ).fetchone()
        roster: list[dict] = []
        keys: dict[UUID, tuple[SigningKey, UUID]] = {}
        for index in range(students):
            student_id = uuid4()
            roll = str(roll_base + index)
            conn.execute(
                "INSERT INTO students (id, roll_number, institutional_email, display_name) VALUES (%s,%s,%s,%s)",
                [student_id, roll, f"{roll.lower()}@example.edu", f"Load Student {index}"],
            )
            conn.execute(
                "INSERT INTO student_credentials (student_id, password_hash, must_change_password) VALUES (%s,%s,false)",
                [student_id, password_hash],
            )
            conn.execute(
                "INSERT INTO enrollments (student_id, course_offering_id, active) VALUES (%s,%s,true)",
                [student_id, offering_id],
            )
            key = SigningKey(roll_base.to_bytes(16, "big") + index.to_bytes(16, "big"))
            public = b64url_encode(bytes(key.verify_key))
            device_id = uuid4()
            conn.execute(
                """
                INSERT INTO device_registrations (id, student_id, public_key, public_key_algorithm,
                    key_fingerprint, platform, status, registered_at)
                VALUES (%s,%s,%s,'Ed25519',%s,'Android','ACTIVE',now())
                """,
                [device_id, student_id, public, public_key_fingerprint(public)],
            )
            keys[student_id] = (key, device_id)
            roster.append({"student_id": student_id, "roll": roll})
        conn.commit()

    session = start_attendance_session(faculty_id, offering_id)
    qr = qr_payload_for(session["id"], now=session["started_at"])
    captured_at = qr["issued_at"] + timedelta(seconds=1)
    for item in roster:
        key, device_id = keys[item["student_id"]]
        sign = lambda payload, key=key: b64url_encode(key.sign(payload).signature)  # noqa: E731
        claim_id, challenge_id, response_id, proof_id = uuid4(), uuid4(), uuid4(), uuid4()
        responded_at = captured_at + timedelta(seconds=2)
        proof_created_at = captured_at + timedelta(seconds=3)
        sid = qr["session_id"]
        claim_sig = sign(canonical_attendance_claim(
            claim_id=claim_id, session_id=sid, student_id=item["student_id"],
            device_registration_id=device_id, qr_epoch=qr["epoch"], qr_challenge=qr["challenge"],
            qr_issued_at=qr["issued_at"].isoformat(), qr_expires_at=qr["expires_at"].isoformat(),
            qr_signature=qr["signature"], qr_captured_at=captured_at.isoformat(),
            claim_created_at=captured_at.isoformat(),
            claim_expires_at=(captured_at + timedelta(seconds=60)).isoformat(),
        ))
        resp_sig = sign(canonical_presence_response(
            response_id=response_id, challenge_id=challenge_id, session_id=sid, claim_id=claim_id,
            device_registration_id=device_id, presence_epoch=1, responded_at=responded_at.isoformat(),
            transport="QR_ASSISTED_WEBRTC_DATA_CHANNEL", challenge_nonce="nonce-load", host_public_key="host-load",
        ))
        proof_sig = sign(canonical_attendance_proof(
            proof_id=proof_id, claim_id=claim_id, session_id=sid, student_id=item["student_id"],
            device_registration_id=device_id, presence_challenge_id=challenge_id,
            presence_response_id=response_id, proof_created_at=proof_created_at.isoformat(),
        ))
        common = {"claim_id": str(claim_id), "session_id": str(sid)}
        item["submission"] = {
            "protocol_version": ATTENDANCE_PROOF_PROTOCOL,
            "claim": {
                **common, "student_id": str(item["student_id"]), "device_registration_id": str(device_id),
                "qr_epoch": qr["epoch"], "qr_challenge": qr["challenge"],
                "qr_issued_at": qr["issued_at"].isoformat(), "qr_expires_at": qr["expires_at"].isoformat(),
                "qr_signature": qr["signature"], "qr_captured_at": captured_at.isoformat(),
                "claim_created_at": captured_at.isoformat(),
                "claim_expires_at": (captured_at + timedelta(seconds=60)).isoformat(),
                "device_signature": claim_sig,
            },
            "challenge": {
                "challenge_id": str(challenge_id), **common, "presence_epoch": 1, "nonce": "nonce-load",
                "issued_at": captured_at.isoformat(),
                "expires_at": (captured_at + timedelta(seconds=20)).isoformat(),
                "transport": "QR_ASSISTED_WEBRTC_DATA_CHANNEL", "host_public_key": "host-load",
            },
            "response": {
                "response_id": str(response_id), "challenge_id": str(challenge_id), **common,
                "device_registration_id": str(device_id), "presence_epoch": 1,
                "responded_at": responded_at.isoformat(), "transport": "QR_ASSISTED_WEBRTC_DATA_CHANNEL",
                "challenge_nonce": "nonce-load", "host_public_key": "host-load", "device_signature": resp_sig,
            },
            "proof": {
                "proof_id": str(proof_id), **common, "student_id": str(item["student_id"]),
                "device_registration_id": str(device_id), "presence_challenge_id": str(challenge_id),
                "presence_response_id": str(response_id), "proof_created_at": proof_created_at.isoformat(),
                "final_device_signature": proof_sig,
            },
        }
    return {"roster": roster}


def _call(method: str, url: str, headers: dict, body: dict | None = None) -> tuple[int, dict, float]:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={"Content-Type": "application/json", **headers})
    started = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            payload = json.load(response)
            status = response.status
    except urllib.error.HTTPError as exc:
        status = exc.code
        try:
            payload = json.load(exc)
        except Exception:
            payload = {}
    except Exception:
        status, payload = 0, {}
    return status, payload, time.perf_counter() - started


def class_start_main(args: argparse.Namespace) -> None:
    fixtures = _prepare_class_start(args.students, args.roll_base)
    roster = fixtures["roster"]
    base = args.base_url.rstrip("/")
    samples: dict[str, list[float]] = {"login": [], "bootstrap": [], "proof_batch": []}
    errors: dict[str, int] = {"login": 0, "bootstrap": 0, "proof_batch": 0}
    results: dict[str, int] = {}
    lock = threading.Lock()

    def record(name: str, status: int, elapsed: float, ok: bool) -> None:
        with lock:
            samples[name].append(elapsed)
            if not ok:
                errors[name] += 1

    def flow(index: int) -> None:
        student = roster[index % len(roster)]
        forwarded = {"X-Forwarded-For": f"10.{(index // 65025) % 250}.{(index // 255) % 255}.{index % 255 + 1}"}
        status, payload, elapsed = _call(
            "POST", f"{base}/api/v1/student/auth/login", forwarded,
            {"roll_number": student["roll"], "password": PASSWORD},
        )
        record("login", status, elapsed, status == 200 and "access_token" in payload)
        if status != 200:
            return
        auth = {**forwarded, "Authorization": f"Bearer {payload['access_token']}"}
        status, _payload, elapsed = _call("GET", f"{base}/api/v1/sync/bootstrap", auth)
        record("bootstrap", status, elapsed, status == 200)
        status, payload, elapsed = _call(
            "POST", f"{base}/api/v1/attendance/proofs/batch", auth, {"proofs": [student["submission"]]},
        )
        outcome = (payload.get("results") or [{}])[0].get("result") if status == 200 else f"HTTP_{status}"
        with lock:
            results[str(outcome)] = results.get(str(outcome), 0) + 1
        record("proof_batch", status, elapsed, status == 200 and outcome in {"ACCEPTED", "ALREADY_ACCEPTED"})

    interval = 60.0 / args.logins_per_min
    total = int(args.duration * args.logins_per_min / 60)
    started = time.perf_counter()
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = []
        for index in range(total):
            delay = started + index * interval - time.perf_counter()
            if delay > 0:
                time.sleep(delay)
            futures.append(pool.submit(flow, index))
        for future in futures:
            future.result()
    wall = time.perf_counter() - started
    report = {"flows": total, "wall_seconds": round(wall, 1), "proof_results": results}
    for name, values in samples.items():
        values.sort()
        report[name] = {
            "n": len(values),
            "p50_ms": _percentile(values, 0.50),
            "p95_ms": _percentile(values, 0.95),
            "max_ms": round(values[-1] * 1000, 1) if values else 0,
            "error_rate": round(errors[name] / max(1, len(values)), 4),
        }
    print(json.dumps(report, indent=2))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scenario", choices=["ready", "class-start"], default="ready")
    parser.add_argument("--url", default="http://127.0.0.1:8000/api/v1/health/ready")
    parser.add_argument("--requests", type=int, default=200)
    parser.add_argument("--workers", type=int, default=20)
    parser.add_argument("--base-url", default="http://127.0.0.1:8000")
    parser.add_argument("--students", type=int, default=300)
    parser.add_argument("--roll-base", type=int, default=91000000, help="first synthetic roll number; change per run")
    parser.add_argument("--logins-per-min", type=int, default=200)
    parser.add_argument("--duration", type=int, default=60, help="seconds of arrivals (class-start)")
    args = parser.parse_args()
    if args.scenario == "class-start":
        class_start_main(args)
    else:
        readiness_main(args)


if __name__ == "__main__":
    main()
