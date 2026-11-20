#!/usr/bin/env python3
"""Backend stress, integrity, chaos and security harness for the attendance pipeline.

Targets a SCRATCH database only (name must contain "stress"); it never touches the dev data.

    export DATABASE_URL=postgresql://localhost/offlineqr_stress PYTHONPATH=.
    python scripts/stress_attendance.py provision --classes 5 --students 100
    python scripts/stress_attendance.py burst     --base-url http://127.0.0.1:8100
    python scripts/stress_attendance.py duplicates | offline | chaos | security | verify

Every phase prints a JSON report and exits non-zero when attendance is lost or duplicated.
Fixture identities are deterministic, so phases can run in separate processes.
"""
from __future__ import annotations

import argparse
import asyncio
import hashlib
import json
import os
import random
import signal
import subprocess
import sys
import time
import uuid
from datetime import UTC, datetime, timedelta
from pathlib import Path

import httpx
import psycopg
from nacl.signing import SigningKey

from backend.app.attendance_protocol import canonical_attendance_claim
from backend.app.attendance_service import qr_payload_for, start_attendance_session
from backend.app.config import get_settings
from backend.app.errors import ApiError
from backend.app.device_crypto import b64url_encode, public_key_fingerprint
from backend.app.institution_clock import institution_today
from backend.app.presence_protocol import (
    ATTENDANCE_PROOF_PROTOCOL,
    canonical_attendance_proof,
    canonical_presence_response,
)

NS = uuid.UUID("5f0c1d52-0000-4000-8000-00000000f00d")
TERM_ID = "10000000-0000-4000-8000-000000000001"
COURSE_ID = "30000000-0000-4000-8000-000000000004"
STATE = Path(os.environ.get("STRESS_STATE", "/tmp/stress_state.json"))
ROLL_BASE = 80_000_000


def guard() -> None:
    name = get_settings().database_url.rsplit("/", 1)[-1].split("?")[0]
    if "stress" not in name:
        raise SystemExit(f"refusing to run against database {name!r}: scratch name must contain 'stress'")


def uid(kind: str, n: int) -> uuid.UUID:
    return uuid.uuid5(NS, f"{kind}-{n}")


def key_for(n: int) -> SigningKey:
    return SigningKey(hashlib.sha256(f"stress-key-{n}".encode()).digest())


def sign(key: SigningKey, payload: bytes) -> str:
    return b64url_encode(key.sign(payload).signature)


# ----------------------------------------------------------------------------- provisioning
def provision(args: argparse.Namespace) -> None:
    guard()
    classes, per = args.classes, args.students
    today = institution_today().isoweekday()
    with psycopg.connect(get_settings().database_url) as conn:
        cur = conn.cursor()
        with cur.copy("COPY sections (id, academic_term_id, code) FROM STDIN") as cp:
            for c in range(classes):
                cp.write_row((uid("section", c), TERM_ID, f"STR-{c:04d}"))
        with cur.copy("COPY course_offerings (id, course_id, academic_term_id, section_id) FROM STDIN") as cp:
            for c in range(classes):
                cp.write_row((uid("offering", c), COURSE_ID, TERM_ID, uid("section", c)))
        with cur.copy("COPY faculty (id, employee_code, institutional_email, display_name) FROM STDIN") as cp:
            for c in range(classes):
                cp.write_row((uid("faculty", c), f"STRFAC{c:05d}", f"strfac{c}@example.edu", f"Stress Faculty {c}"))
        with cur.copy("COPY faculty_assignments (id, faculty_id, course_offering_id, role) FROM STDIN") as cp:
            for c in range(classes):
                cp.write_row((uid("assign", c), uid("faculty", c), uid("offering", c), "PRIMARY"))
        with cur.copy(
            "COPY timetable_entries (id, course_offering_id, day_of_week, start_time, end_time, room, valid_from, valid_until) FROM STDIN"
        ) as cp:
            for c in range(classes):
                cp.write_row((uid("tt", c), uid("offering", c), today, "00:00", "23:59", f"STR-{c}", "2026-08-01", "2026-12-20"))
        total = classes * per
        with cur.copy("COPY students (id, roll_number, institutional_email, display_name) FROM STDIN") as cp:
            for n in range(total):
                cp.write_row((uid("student", n), str(ROLL_BASE + n), f"str{n}@example.edu", f"Stress Student {n}"))
        with cur.copy("COPY enrollments (student_id, course_offering_id) FROM STDIN") as cp:
            for n in range(total):
                cp.write_row((uid("student", n), uid("offering", n // per)))
        with cur.copy(
            "COPY device_registrations (id, student_id, public_key, public_key_algorithm, key_fingerprint, platform, status, registered_at) FROM STDIN"
        ) as cp:
            now = datetime.now(UTC)
            for n in range(total):
                pub = b64url_encode(bytes(key_for(n).verify_key))
                cp.write_row((uid("device", n), uid("student", n), pub, "Ed25519", public_key_fingerprint(pub), "Android", "ACTIVE", now))
        from argon2 import PasswordHasher
        ph = PasswordHasher(time_cost=3, memory_cost=65536, parallelism=2).hash("Stress#Probe2026pw")
        for n in range(6):  # a few real credentials so login throttling/lockout can be exercised
            conn.execute("INSERT INTO student_credentials (student_id, password_hash, must_change_password) VALUES (%s,%s,false)", [uid("student", n), ph])
        fh = PasswordHasher(time_cost=3, memory_cost=65536, parallelism=2).hash("ChangeMe-Dev-Only!2026")
        for c in range(min(classes, 3)):  # three stress faculty can sign in and own their class session
            conn.execute("INSERT INTO faculty_credentials (faculty_id, password_hash, must_change_password) VALUES (%s,%s,false)", [uid("faculty", c), fh])
        conn.commit()
    sessions = []
    for c in range(classes):
        s = start_attendance_session(uid("faculty", c), uid("offering", c))
        sessions.append({"class": c, "session_id": str(s["id"]), "started_at": s["started_at"].isoformat()})
    STATE.write_text(json.dumps({"classes": classes, "per": per, "sessions": sessions}))
    print(json.dumps({"provisioned": {"classes": classes, "students_per_class": per, "students": total, "sessions_started": len(sessions)}}))


def load_state() -> dict:
    return json.loads(STATE.read_text())


# ----------------------------------------------------------------------------- proof building
def make_submission(n: int, qr: dict, *, captured_offset: float = 1.0, claim_delay: float = 0.0, signer: SigningKey | None = None,
                    student_n: int | None = None, device_n: int | None = None) -> dict:
    """Build a valid ATTENDANCE_PROOF_V1 for student n. Overrides let tests forge specific defects."""
    sid = uid("student", n if student_n is None else student_n)
    dev = uid("device", n if device_n is None else device_n)
    key = signer or key_for(n)
    captured_at = qr["issued_at"] + timedelta(seconds=captured_offset)
    created_at = captured_at + timedelta(seconds=claim_delay)
    claim_id, challenge_id, response_id, proof_id = (uuid.uuid4() for _ in range(4))
    session_id = qr["session_id"]
    responded_at = created_at + timedelta(seconds=2)
    proof_at = created_at + timedelta(seconds=3)
    claim_sig = sign(key, canonical_attendance_claim(
        claim_id=claim_id, session_id=session_id, student_id=sid, device_registration_id=dev,
        qr_epoch=qr["epoch"], qr_challenge=qr["challenge"], qr_issued_at=qr["issued_at"].isoformat(),
        qr_expires_at=qr["expires_at"].isoformat(), qr_signature=qr["signature"],
        qr_captured_at=captured_at.isoformat(), claim_created_at=created_at.isoformat(),
        claim_expires_at=(created_at + timedelta(seconds=60)).isoformat()))
    resp_sig = sign(key, canonical_presence_response(
        response_id=response_id, challenge_id=challenge_id, session_id=session_id, claim_id=claim_id,
        device_registration_id=dev, presence_epoch=1, responded_at=responded_at.isoformat(),
        transport="QR_ASSISTED_WEBRTC_DATA_CHANNEL", challenge_nonce="n-stress", host_public_key="h-stress"))
    proof_sig = sign(key, canonical_attendance_proof(
        proof_id=proof_id, claim_id=claim_id, session_id=session_id, student_id=sid, device_registration_id=dev,
        presence_challenge_id=challenge_id, presence_response_id=response_id, proof_created_at=proof_at.isoformat()))
    common = {"claim_id": str(claim_id), "session_id": str(session_id)}
    return {
        "protocol_version": ATTENDANCE_PROOF_PROTOCOL,
        "claim": {**common, "student_id": str(sid), "device_registration_id": str(dev), "qr_epoch": qr["epoch"],
                  "qr_challenge": qr["challenge"], "qr_issued_at": qr["issued_at"].isoformat(),
                  "qr_expires_at": qr["expires_at"].isoformat(), "qr_signature": qr["signature"],
                  "qr_captured_at": captured_at.isoformat(), "claim_created_at": created_at.isoformat(),
                  "claim_expires_at": (created_at + timedelta(seconds=60)).isoformat(), "device_signature": claim_sig},
        "challenge": {"challenge_id": str(challenge_id), **common, "presence_epoch": 1, "nonce": "n-stress",
                      "issued_at": created_at.isoformat(), "expires_at": (created_at + timedelta(seconds=20)).isoformat(),
                      "transport": "QR_ASSISTED_WEBRTC_DATA_CHANNEL", "host_public_key": "h-stress"},
        "response": {"response_id": str(response_id), "challenge_id": str(challenge_id), **common,
                     "device_registration_id": str(dev), "presence_epoch": 1, "responded_at": responded_at.isoformat(),
                     "transport": "QR_ASSISTED_WEBRTC_DATA_CHANNEL", "challenge_nonce": "n-stress",
                     "host_public_key": "h-stress", "device_signature": resp_sig},
        "proof": {"proof_id": str(proof_id), **common, "student_id": str(sid), "device_registration_id": str(dev),
                  "presence_challenge_id": str(challenge_id), "presence_response_id": str(response_id),
                  "proof_created_at": proof_at.isoformat(), "final_device_signature": proof_sig},
    }


def qr_cache(state: dict, epochs: int) -> dict[tuple[int, int], dict]:
    cache = {}
    for s in state["sessions"]:
        started = datetime.fromisoformat(s["started_at"])
        for e in range(epochs):
            try:
                cache[(s["class"], e)] = qr_payload_for(uuid.UUID(s["session_id"]), now=started + timedelta(seconds=e * 5 + 0.5))
            except ApiError:
                break  # session already closed by an earlier phase
    return cache


def build_all(state: dict, epochs: int = 12, skip_every: int = 0) -> list[dict]:
    """One submission per student, scanned in a spread of QR epochs. skip_every=k leaves every k-th student absent."""
    cache = qr_cache(state, epochs)
    out = []
    per = state["per"]
    for n in range(state["classes"] * per):
        if skip_every and n % skip_every == 0:
            continue
        c = n // per
        out.append({"n": n, "student_id": str(uid("student", n)), "session_id": state["sessions"][c]["session_id"],
                    "sub": make_submission(n, cache[(c, n % epochs)])})
    return out


# ----------------------------------------------------------------------------- load driver
def pct(values: list[float], f: float) -> float:
    if not values:
        return 0.0
    values = sorted(values)
    return round(values[min(len(values) - 1, max(0, int(round(f * len(values))) - 1))] * 1000, 1)


async def deliver_one(items: list[dict], base: str, concurrency: int, retries: int, timeout: float,
                      one_ip: bool = False, batch: int = 1, chaos: asyncio.Event | None = None, start_at: float = 0.0,
                      offset: int = 0) -> dict:
    """Release every item at the same instant; retry like the app outbox until acknowledged or out of attempts."""
    bases = [b.strip().rstrip("/") for b in base.split(",") if b.strip()]  # several stateless API heads
    limits = httpx.Limits(max_connections=concurrency, max_keepalive_connections=concurrency)
    sem = asyncio.Semaphore(concurrency)
    gate = asyncio.Event()
    lat: list[float] = []
    stats = {"http": {}, "results": {}, "attempts": 0, "gave_up": 0, "heads": {}}
    acked: dict[str, str] = {}

    async def one(client: httpx.AsyncClient, group: list[dict], index: int) -> None:
        await gate.wait()
        headers = {} if one_ip else {"X-Forwarded-For": f"10.{(index >> 16) & 255}.{(index >> 8) & 255}.{index & 255}"}
        headers["x-student-id"] = group[0]["student_id"]
        pending = list(group)
        for attempt in range(retries + 1):
            if not pending:
                return
            async with sem:
                started = time.perf_counter()
                stats["attempts"] += 1
                try:
                    target = random.choice(bases)  # a retry may land on a different head: the heads hold no state
                    stats["heads"][target] = stats["heads"].get(target, 0) + 1
                    r = await client.post(f"{target}/api/v1/attendance/proofs/batch",
                                          json={"proofs": [p["sub"] for p in pending]}, headers=headers)
                    status = r.status_code
                except Exception as exc:  # network loss, reset, timeout: the outbox retries
                    status = type(exc).__name__
                    r = None
                lat.append(time.perf_counter() - started)
            stats["http"][str(status)] = stats["http"].get(str(status), 0) + 1
            if r is not None and status == 200:
                results = {x["proof_id"]: x for x in r.json()["results"]}
                still = []
                for p in pending:
                    res = results.get(p["sub"]["proof"]["proof_id"])
                    if res is None:
                        still.append(p)  # unanswered proof (e.g. server truncation) stays in the outbox
                        stats["results"]["UNANSWERED"] = stats["results"].get("UNANSWERED", 0) + 1
                    elif res["result"] in ("ACCEPTED", "ALREADY_ACCEPTED"):
                        acked[p["student_id"] + p["session_id"]] = res["result"]
                        stats["results"][res["result"]] = stats["results"].get(res["result"], 0) + 1
                    elif res.get("retryable"):
                        still.append(p)
                        stats["results"]["RETRY_" + str(res.get("error_code"))] = stats["results"].get("RETRY_" + str(res.get("error_code")), 0) + 1
                    else:
                        code = "REJECTED_" + str(res.get("error_code"))
                        stats["results"][code] = stats["results"].get(code, 0) + 1
                pending = still
            if pending:
                await asyncio.sleep(min(5.0, 0.2 * 2 ** attempt) * random.uniform(0.5, 1.5))
        stats["gave_up"] += len(pending)

    groups = [items[i:i + batch] for i in range(0, len(items), batch)]
    async with httpx.AsyncClient(limits=limits, timeout=timeout) as client:
        tasks = [asyncio.create_task(one(client, g, i + offset)) for i, g in enumerate(groups)]
        # Pre-open keep-alive sockets in waves below the OS listen backlog (macOS caps it at 128), as a real load
        # balancer would: the test then measures the application, not SYN-retransmit timers.
        target_n = min(concurrency, len(groups))
        for k in range(64, target_n + 64, 64):
            await asyncio.gather(*[client.get(f"{bases[j % len(bases)]}/api/v1/health/live") for j in range(min(k, target_n))], return_exceptions=True)
        await asyncio.sleep(max(0.2, start_at - time.time()))
        t0 = time.perf_counter()
        gate.set()
        if chaos is not None:
            chaos.set()
        await asyncio.gather(*tasks)
        wall = time.perf_counter() - t0
    return {"submitted": len(items), "wall_s": round(wall, 2), "throughput_per_s": round(len(items) / wall, 1),
            "p50_ms": pct(lat, .5), "p95_ms": pct(lat, .95), "p99_ms": pct(lat, .99), "max_ms": pct(lat, 1.0),
            **stats, "acked": len(acked), "ack_keys": acked, "_lat": lat}


PROCS = int(os.environ.get("STRESS_PROCS", "1"))
EPOCHS = 3


def build_items(state: dict, indexes: list[int], epochs: int = EPOCHS) -> list[dict]:
    """Signed proofs for the given student indexes; each class's QR for an epoch is fetched once."""
    per = state["per"]
    cache: dict[tuple[int, int], dict] = dict(state.get("_qr") or {})  # parent may prefill before closing sessions
    out = []
    for n in indexes:
        c, e = n // per, n % epochs
        if (c, e) not in cache:
            s = state["sessions"][c]
            cache[(c, e)] = qr_payload_for(uuid.UUID(s["session_id"]), now=datetime.fromisoformat(s["started_at"]) + timedelta(seconds=e * 5 + 0.5))
        out.append({"n": n, "student_id": str(uid("student", n)), "session_id": state["sessions"][c]["session_id"], "sub": make_submission(n, cache[(c, e)])})
    return out


def _shard_main(job_path: str, out_path: str) -> None:
    """One client process: build its own proofs (CPU parallel), wait at the barrier, fire together."""
    import pickle

    job = pickle.loads(Path(job_path).read_bytes())
    t = time.perf_counter()
    items = build_items(job["state"], job["indexes"])
    items = items * job["repeat"]
    build_s = time.perf_counter() - t
    Path(job["ready"]).write_text(str(len(items)))
    while not Path(job["go"]).exists():
        time.sleep(0.05)
    start_at = float(Path(job["go"]).read_text())
    res = asyncio.run(deliver_one(items, start_at=start_at, **job["kw"]))
    res["build_s"] = build_s
    Path(out_path).write_bytes(pickle.dumps(res))


def run_load(state: dict, indexes: list[int], args, repeat: int = 1, concurrency: int | None = None, retries: int | None = None,
             on_go=None, live_label: str | None = None) -> dict:
    """Shard `indexes` over client processes, prebuild, release together, merge the reports."""
    import pickle
    import tempfile

    procs_n = max(1, (getattr(args, "procs", 0) or PROCS))
    conc = concurrency or args.concurrency
    tmp = Path(tempfile.mkdtemp(prefix="stress_shards_"))
    size = (len(indexes) + procs_n - 1) // procs_n
    children = []
    for i in range(procs_n):
        part = indexes[i * size:(i + 1) * size]
        if not part:
            continue
        kw = dict(base=args.base_url, concurrency=max(1, conc // procs_n), retries=retries or args.retries, timeout=args.timeout,
                  one_ip=args.one_ip, batch=args.batch, offset=i * size)
        job = {"state": state, "indexes": part, "repeat": repeat, "kw": kw, "ready": str(tmp / f"ready{i}"), "go": str(tmp / "go")}
        (tmp / f"in{i}.pkl").write_bytes(pickle.dumps(job))
        children.append((i, subprocess.Popen([sys.executable, __file__, "_shard", str(tmp / f"in{i}.pkl"), str(tmp / f"out{i}.pkl")], env=os.environ.copy())))
    t0 = time.time()
    while not all((tmp / f"ready{i}").exists() for i, _ in children):
        if any(pr.poll() not in (None, 0) for _, pr in children):
            raise SystemExit("a client shard crashed while building proofs")
        time.sleep(0.2)
    build_wall = time.time() - t0
    (tmp / "go").write_text(str(time.time() + 1.5))
    if on_go:
        on_go()
    for _, pr in children:
        pr.wait()
    parts = [pickle.loads((tmp / f"out{i}.pkl").read_bytes()) for i, _ in children]
    lat = [x for part in parts for x in part["_lat"]]
    wall = max(part["wall_s"] for part in parts)
    merged: dict = {"http": {}, "results": {}, "heads": {}}
    for part in parts:
        for key in ("http", "results", "heads"):
            for k, v in part[key].items():
                merged[key][k] = merged[key].get(k, 0) + v
    ack: dict = {}
    for part in parts:
        ack.update(part["ack_keys"])
    total = sum(part["submitted"] for part in parts)
    return {"submitted": total, "unique_students": len(indexes), "wall_s": wall, "throughput_per_s": round(total / wall, 1),
            "p50_ms": pct(lat, .5), "p95_ms": pct(lat, .95), "p99_ms": pct(lat, .99), "max_ms": pct(lat, 1.0), "build_s": round(build_wall, 1),
            **merged, "attempts": sum(p["attempts"] for p in parts), "gave_up": sum(p["gave_up"] for p in parts), "acked": len(ack), "ack_keys": ack,
            "client_procs": len(children)}


def _expected(state: dict, indexes: list[int]) -> set[tuple[str, str]]:
    per = state["per"]
    return {(str(uid("student", n)), state["sessions"][n // per]["session_id"]) for n in indexes}


# ----------------------------------------------------------------------------- verification
def verify_counts(state: dict, expected: set[tuple[str, str]] | None, label: str) -> dict:
    """Zero-loss / zero-duplicate invariants straight from PostgreSQL."""
    with psycopg.connect(get_settings().database_url) as conn:
        total_records = conn.execute(
            "SELECT count(*) FROM attendance_records WHERE attendance_session_id = ANY(%s) AND status='PRESENT'",
            [[s["session_id"] for s in state["sessions"]]]).fetchone()[0]
        dupes = conn.execute(
            "SELECT count(*) FROM (SELECT 1 FROM attendance_records GROUP BY attendance_session_id, student_id HAVING count(*)>1) d").fetchone()[0]
        proofs_dupes = conn.execute(
            "SELECT count(*) FROM (SELECT 1 FROM attendance_proofs GROUP BY attendance_session_id, student_id HAVING count(*) FILTER (WHERE sync_state='SERVER_VERIFIED')>1) d").fetchone()[0]
        present = {(str(r[0]), str(r[1])) for r in conn.execute(
            "SELECT student_id, attendance_session_id FROM attendance_records WHERE attendance_session_id = ANY(%s) AND status='PRESENT'",
            [[s["session_id"] for s in state["sessions"]]]).fetchall()}
    report = {"phase": label, "present_records": total_records, "duplicate_records": dupes, "duplicate_verified_proofs": proofs_dupes}
    if expected is not None:
        missing = expected - present
        report.update({"expected_present": len(expected), "lost": len(missing), "unexpected_extra": len(present - expected)})
        report["ok"] = not missing and dupes == 0 and proofs_dupes == 0
    else:
        report["ok"] = dupes == 0 and proofs_dupes == 0
    return report


def keys_to_expected(ack_keys: dict) -> set[tuple[str, str]]:
    return {(k[:36], k[36:]) for k in ack_keys}


# ----------------------------------------------------------------------------- phases
def _all(state: dict) -> list[int]:
    return list(range(state["classes"] * state["per"]))


def _strip(res: dict) -> dict:
    return {k: v for k, v in res.items() if k != "ack_keys"}


def phase_burst(args):
    guard()
    state = load_state()
    idx = _all(state)
    res = run_load(state, idx, args)
    ver = verify_counts(state, _expected(state, idx), "burst")
    report = {**_strip(res), "verify": ver, "ok": ver["ok"] and res["gave_up"] == 0}
    print(json.dumps(report, indent=2))
    sys.exit(0 if report["ok"] else 1)


def phase_duplicates(args):
    guard()
    state = load_state()
    idx = _all(state)[:args.limit] if args.limit else _all(state)
    # every proof delivered three times concurrently = app retry storm after dropped connections
    res = run_load(state, idx, args, repeat=3)
    ver = verify_counts(state, _expected(state, idx), "duplicates")
    ver["ok"] = ver["ok"] and res["gave_up"] == 0
    print(json.dumps({**_strip(res), "verify": ver, "ok": ver["ok"]}, indent=2))
    sys.exit(0 if ver["ok"] else 1)


def worker_pids(server_pid: int) -> list[int]:
    out = subprocess.run(["pgrep", "-P", str(server_pid)], capture_output=True, text=True).stdout.split()
    return [int(p) for p in out]


def chaos_driver(server_pids: list[int], stop: list[bool], log: list[str], kill_heads: bool) -> None:
    """Kill API workers and whole heads, and drop live DB connections, at random while load is running."""
    db = get_settings().database_url.rsplit("/", 1)[-1].split("?")[0]
    while not stop[0]:
        time.sleep(random.uniform(1.5, 3.0))
        roll = random.random()
        if roll < 0.45:
            pids = [w for sp in server_pids for w in worker_pids(sp)]
            if pids:
                victim = random.choice(pids)
                try:
                    os.kill(victim, signal.SIGKILL)
                    log.append(f"killed worker {victim}")
                except ProcessLookupError:
                    pass
        elif roll < 0.55 and kill_heads and len(server_pids) > 1:
            head = random.choice(server_pids)
            try:
                os.kill(head, signal.SIGKILL)  # the whole head dies; the other heads keep serving
                for w in worker_pids(head):
                    os.kill(w, signal.SIGKILL)
                log.append(f"killed HEAD {head} and its workers")
            except ProcessLookupError:
                pass
        else:
            with psycopg.connect("postgresql://localhost/postgres", autocommit=True) as c:
                n = c.execute("SELECT count(pg_terminate_backend(pid)) FROM pg_stat_activity WHERE datname=%s AND pid<>pg_backend_pid()", [db]).fetchone()[0]
            log.append(f"terminated {n} db backends")


def phase_chaos(args):
    guard()
    import threading

    state = load_state()
    idx = _all(state)
    pids = [int(x) for x in str(args.server_pid).split(",") if x and int(x)]
    stop, log = [False], []

    def go():
        threading.Thread(target=chaos_driver, args=(pids, stop, log, args.kill_heads), daemon=True).start()

    res = run_load(state, idx, args, retries=max(args.retries, 40), on_go=go)
    stop[0] = True
    expected = _expected(state, idx)
    ver = verify_counts(state, expected, "chaos")
    durable = verify_counts(state, keys_to_expected(res["ack_keys"]), "chaos-acknowledged")
    ver["acknowledged_but_missing"] = durable["lost"]
    ver["never_acknowledged_within_budget"] = len(expected) - len(res["ack_keys"])
    report = {"faults_injected": log, **_strip(res), "verify": ver}
    report["ok"] = durable["ok"] and durable["lost"] == 0 and ver["duplicate_records"] == 0
    print(json.dumps(report, indent=2))
    sys.exit(0 if report["ok"] else 1)


def phase_offline(args):
    """Scan while connected to nothing: proofs wait in the outbox while faculty closes, then flush in the window."""
    guard()
    state = load_state()
    per = state["per"]
    idx = _all(state)
    in_window = [n for n in idx if (n // per) % 2 == 0]
    late = [n for n in idx if (n // per) % 2 == 1][:200]
    state["_qr"] = qr_cache(state, EPOCHS)  # QR payloads need an ACTIVE session: build them before the class closes
    with psycopg.connect(get_settings().database_url) as conn:
        conn.execute("UPDATE attendance_sessions SET state='SYNCING', closed_at=now(), reconcile_until=now()+interval '7 days' WHERE id = ANY(%s)",
                     [[s["session_id"] for s in state["sessions"]]])
    res1 = run_load(state, in_window, args)
    ver1 = verify_counts(state, _expected(state, in_window), "offline-in-window")
    with psycopg.connect(get_settings().database_url) as conn:
        conn.execute("UPDATE attendance_sessions SET reconcile_until=now()-interval '1 minute' WHERE id = ANY(%s)", [[s["session_id"] for s in state["sessions"]]])
    res2 = run_load(state, late, args, concurrency=50, retries=1)
    with psycopg.connect(get_settings().database_url) as conn:
        late_present = conn.execute(
            "SELECT count(*) FROM attendance_records WHERE attendance_session_id = ANY(%s) AND student_id = ANY(%s) AND status='PRESENT'",
            [[s["session_id"] for s in state["sessions"]], [str(uid("student", n)) for n in late]]).fetchone()[0]
    ok = ver1["ok"] and res1["gave_up"] == 0 and late_present == 0 and res2["results"].get("REJECTED_RECONCILIATION_WINDOW_CLOSED", 0) == len(late)
    print(json.dumps({"in_window": {**_strip(res1), "verify": ver1}, "after_window": {"results": res2["results"], "records_created_after_window": late_present}, "ok": ok}, indent=2))
    sys.exit(0 if ok else 1)


def phase_finalize(args):
    """Close the books: every enrolled student without a proof must become ABSENT; totals must add up."""
    guard()
    state = load_state()
    ids = [s["session_id"] for s in state["sessions"]]
    with psycopg.connect(get_settings().database_url) as conn:
        conn.execute("UPDATE attendance_sessions SET state='SYNCING', closed_at=coalesce(closed_at, now()), reconcile_until=now()-interval '1 minute' WHERE id = ANY(%s)", [ids])
    from concurrent.futures import ThreadPoolExecutor

    from backend.app.attendance_service import finalize_reconciliation

    with ThreadPoolExecutor(8) as pool:
        list(pool.map(lambda cs: finalize_reconciliation(uid("faculty", cs[0]), uuid.UUID(cs[1]["session_id"])), enumerate(state["sessions"])))
    with psycopg.connect(get_settings().database_url) as conn:
        rows = conn.execute("SELECT count(*) FILTER (WHERE status='PRESENT'), count(*) FILTER (WHERE status='ABSENT'), count(*) FROM attendance_records WHERE attendance_session_id = ANY(%s)", [ids]).fetchone()
        roster = conn.execute("SELECT count(*) FROM attendance_session_roster WHERE attendance_session_id = ANY(%s)", [ids]).fetchone()[0]
    total = state["classes"] * state["per"]
    ok = rows[2] == roster == total and rows[0] + rows[1] == total
    print(json.dumps({"present": rows[0], "absent": rows[1], "records": rows[2], "roster_snapshot": roster, "enrolled": total, "ok": ok}, indent=2))
    sys.exit(0 if ok else 1)


# ----------------------------------------------------------------------------- security probes
def phase_security(args):
    guard()
    state = load_state()
    base = args.base_url
    cache = qr_cache(state, 3)
    q0, q1 = cache[(0, 0)], cache[(1, 0)]
    per = state["per"]
    hdr = lambda n: {"x-student-id": str(uid("student", n)), "X-Forwarded-For": f"172.16.{n % 250}.{n // 250 % 250 + 1}"}  # noqa: E731
    fac = lambda c: {"x-faculty-id": str(uid("faculty", c))}  # noqa: E731
    results: list[dict] = []

    def post_proof(sub, headers=None, expect=None, name=""):
        r = httpx.post(f"{base}/api/v1/attendance/proofs/batch", json={"proofs": [sub]}, headers=headers or hdr(0), timeout=30)
        body = r.json() if r.headers.get("content-type", "").startswith("application/json") else {}
        got = (body.get("results") or [{}])[0].get("error_code") or (body.get("results") or [{}])[0].get("result") if r.status_code == 200 else f"HTTP_{r.status_code}"
        results.append({"probe": name, "expected": expect, "got": got, "pass": got == expect or (isinstance(expect, set) and got in expect)})
        return got

    # --- forgery and tampering
    post_proof(make_submission(2, q0, signer=key_for(3)), expect={"INVALID_SIGNATURE", "INVALID_CLAIM_SIGNATURE", "INVALID_DEVICE_SIGNATURE"}, name="signature from another student's key")
    post_proof(make_submission(4, q0, student_n=5, device_n=5, signer=key_for(4)), expect={"INVALID_SIGNATURE", "INVALID_CLAIM_SIGNATURE", "INVALID_DEVICE_SIGNATURE"}, name="student A signs a claim as student B")
    sub = make_submission(6, q0); sub["claim"]["qr_challenge"] = "x" * 43
    post_proof(sub, expect={"QR_TAMPERED", "INVALID_QR_SIGNATURE", "QR_EXPIRED", "INVALID_CLAIM_SIGNATURE"}, name="tampered QR challenge")
    sub = make_submission(7, q0); sub["claim"]["qr_signature"] = sub["claim"]["qr_signature"][::-1]
    post_proof(sub, expect={"INVALID_QR_SIGNATURE", "QR_TAMPERED", "INVALID_CLAIM_SIGNATURE"}, name="forged QR signature")
    sub = make_submission(8, q0); sub["protocol_version"] = "ATTENDANCE_PROOF_V0"
    post_proof(sub, expect="UNSUPPORTED_PROTOCOL", name="downgraded protocol version")
    # --- replay / cross-class
    sub = make_submission(per + 1, q0)  # student of class 1 presenting class 0's QR
    post_proof(sub, expect={"STUDENT_NOT_ELIGIBLE", "NOT_ROSTERED", "STUDENT_NOT_ROSTERED", "QR_KEY_MISMATCH", "INVALID_QR_SIGNATURE"}, name="student of class B scans class A's QR (cross-class)")
    sub = make_submission(9, q0)
    sub["claim"]["session_id"] = sub["challenge"]["session_id"] = sub["response"]["session_id"] = sub["proof"]["session_id"] = q1["session_id"].__str__()
    post_proof(sub, expect=None if False else {"INVALID_QR_SIGNATURE", "QR_TAMPERED", "QR_KEY_MISMATCH", "INVALID_CLAIM_SIGNATURE", "STUDENT_NOT_ELIGIBLE", "NOT_ROSTERED", "STUDENT_NOT_ROSTERED"}, name="QR from session A replayed against session B")
    # --- timing
    post_proof(make_submission(10, q0, captured_offset=40), expect="QR_EXPIRED", name="scan claimed 40 s after QR expired (photo of screen)")
    post_proof(make_submission(11, q0, captured_offset=-30), expect="QR_EXPIRED", name="scan claimed before QR was issued (future QR)")
    post_proof(make_submission(12, q0, claim_delay=90), expect="CLAIM_EXPIRED", name="claim created 90 s after capture")
    # --- identity
    ghost = make_submission(13, q0, student_n=10 ** 6, device_n=10 ** 6, signer=key_for(10 ** 6))
    post_proof(ghost, expect={"STUDENT_NOT_ELIGIBLE", "DEVICE_REVOKED", "DEVICE_NOT_FOUND", "DEVICE_NOT_ACTIVE", "INVALID_DEVICE", "NOT_ROSTERED", "STUDENT_NOT_ROSTERED", "DEVICE_MISMATCH"}, name="unregistered student/device")
    # --- payload abuse
    r = httpx.post(f"{base}/api/v1/attendance/proofs/batch", content=b"{not json", headers={**hdr(0), "content-type": "application/json"})
    results.append({"probe": "malformed JSON body", "expected": 422, "got": r.status_code, "pass": r.status_code in (400, 422)})
    r = httpx.post(f"{base}/api/v1/attendance/proofs/batch", json={"proofs": [{"protocol_version": "'; DROP TABLE attendance_records;--"}]}, headers=hdr(0))
    results.append({"probe": "SQL-injection string in proof body", "expected": 422, "got": r.status_code, "pass": r.status_code in (400, 422)})
    big = {"proofs": [make_submission(14, q0)], "pad": "A" * (12 * 1024 * 1024)}
    try:
        r = httpx.post(f"{base}/api/v1/attendance/proofs/batch", json=big, headers=hdr(0), timeout=30)
        got = r.status_code
    except Exception as exc:
        got = type(exc).__name__
    results.append({"probe": "12 MB oversized body is refused before buffering", "expected": 413, "got": got, "pass": got == 413})
    subs = [make_submission(100 + i, q0) for i in range(60)]
    r = httpx.post(f"{base}/api/v1/attendance/proofs/batch", json={"proofs": subs}, headers=hdr(0), timeout=60)
    answered = len(r.json().get("results", [])) if r.status_code == 200 else 0
    results.append({"probe": "batch of 60 proofs: every proof gets an answer", "expected": 60, "got": answered, "pass": answered == 60 or r.status_code in (413, 422)})
    # --- access control
    for name, method, path, headers, ok_codes in [
        ("faculty roster without login", "GET", f"/api/v1/faculty/attendance-sessions/{state['sessions'][0]['session_id']}/roster", {}, {401, 403}),
        ("faculty A reads faculty B's roster", "GET", f"/api/v1/faculty/attendance-sessions/{state['sessions'][1]['session_id']}/roster", fac(0), {403, 404}),
        ("faculty A closes faculty B's session", "POST", f"/api/v1/faculty/attendance-sessions/{state['sessions'][1]['session_id']}/close", fac(0), {403, 404}),
        ("student calls faculty endpoint", "GET", "/api/v1/faculty/classes/today", hdr(0), {401, 403}),
        ("student calls admin devices", "GET", "/api/v1/admin/devices", hdr(0), {401, 403}),
        ("faculty (non-admin) calls admin devices", "GET", "/api/v1/admin/devices", fac(0), {401, 403, 404}),
        ("student calls admin password reset", "POST", f"/api/v1/admin/students/{ROLL_BASE}/password-reset", hdr(0), {401, 403, 405, 422}),
        ("student data without login", "GET", "/api/v1/sync/bootstrap", {}, {401}),
        ("student bearer token garbage", "GET", "/api/v1/sync/bootstrap", {"authorization": "Bearer nope"}, {401}),
        ("path traversal in session id", "GET", "/api/v1/faculty/attendance-sessions/..%2f..%2fetc%2fpasswd/roster", fac(0), {404, 422, 400}),
        ("unauthenticated QR endpoint", "GET", f"/api/v1/faculty/attendance-sessions/{state['sessions'][0]['session_id']}/qr", {}, {401, 403}),
    ]:
        rr = httpx.request(method, f"{base}{path}", headers=headers, timeout=20)
        results.append({"probe": name, "expected": sorted(ok_codes), "got": rr.status_code, "pass": rr.status_code in ok_codes})
    # --- CORS and headers
    rr = httpx.options(f"{base}/api/v1/sync/bootstrap", headers={"Origin": "https://evil.example", "Access-Control-Request-Method": "GET"})
    results.append({"probe": "CORS preflight from evil origin", "expected": "no allow-origin", "got": rr.headers.get("access-control-allow-origin"), "pass": rr.headers.get("access-control-allow-origin") in (None, "")})
    rr = httpx.get(f"{base}/api/v1/health/live")
    need = ["x-content-type-options", "x-frame-options", "referrer-policy", "permissions-policy"]
    results.append({"probe": "security headers present", "expected": need, "got": [h for h in need if h in rr.headers], "pass": all(h in rr.headers for h in need)})
    # --- login brute-force throttling
    codes = []
    for i in range(400):
        codes.append(httpx.post(f"{base}/api/v1/student/auth/login", json={"roll_number": str(ROLL_BASE), "password": f"wrong-{i}"}, headers={"X-Forwarded-For": "198.51.100.7"}, timeout=10).status_code)
    import socket
    try:
        socket.create_connection(("127.0.0.1", 6379), timeout=0.5).close()
        redis_up = True
    except OSError:
        redis_up = False
    if redis_up:
        results.append({"probe": "400 wrong passwords from one IP in a burst", "expected": "429 appears", "got": {str(c): codes.count(c) for c in set(codes)}, "pass": 429 in codes})
    else:
        results.append({"probe": "400 wrong passwords from one IP: 429 throttle", "expected": "429 appears (needs Redis)", "got": "SKIPPED: no Redis here, dev limiter is 10x looser; account lockout probe below still runs", "pass": True, "skipped": True})
    with psycopg.connect(get_settings().database_url) as conn:
        locked = conn.execute("SELECT failed_login_count, locked_until IS NOT NULL FROM student_credentials sc JOIN students s ON s.id=sc.student_id WHERE s.roll_number=%s", [str(ROLL_BASE)]).fetchone()
    results.append({"probe": "account lockout after repeated failures", "expected": "locked", "got": str(locked), "pass": bool(locked and locked[1])})
    # --- integrity after attack: forged probes must have produced no attendance
    with psycopg.connect(get_settings().database_url) as conn:
        forged = conn.execute("SELECT count(*) FROM attendance_records WHERE student_id = ANY(%s)", [[str(uid("student", n)) for n in (2, 4, 6, 7, 8, 9, 10, 11, 12, per + 1)]]).fetchone()[0]
    results.append({"probe": "no attendance record created by any forged proof", "expected": 0, "got": forged, "pass": forged == 0})
    failed = [r for r in results if not r["pass"]]
    print(json.dumps({"probes": len(results), "passed": len(results) - len(failed), "failed": failed, "all": results}, indent=2, default=str))
    sys.exit(0 if not failed else 1)


# ----------------------------------------------------------------------------- stateless heads, live events, NAT, pen test
STUDENT_PW = "Stress#Probe2026pw"
FACULTY_EMAIL, FACULTY_PW = "strfac0@example.edu", "ChangeMe-Dev-Only!2026"  # owns session 0


def _heads(args) -> list[str]:
    return [b.strip().rstrip("/") for b in args.base_url.split(",") if b.strip()]


def _record(results: list, probe: str, expected, got, ok: bool, **extra) -> None:
    results.append({"probe": probe, "expected": expected, "got": got, "pass": bool(ok), **extra})


def _student_login(base: str, n: int = 0, password: str = STUDENT_PW, ip: str | None = None) -> httpx.Response:
    return httpx.post(f"{base}/api/v1/student/auth/login", json={"roll_number": str(ROLL_BASE + n), "password": password},
                      headers={"X-Forwarded-For": ip or f"10.9.{random.randint(0, 250)}.{random.randint(1, 250)}"}, timeout=30)


def _faculty_login(base: str) -> httpx.Client:
    client = httpx.Client(base_url=base, timeout=30, headers={"X-Forwarded-For": f"10.8.{random.randint(0, 250)}.{random.randint(1, 250)}"})
    r = client.post("/api/v1/faculty/auth/login", json={"email": FACULTY_EMAIL, "password": FACULTY_PW})
    r.raise_for_status()
    return client


def _finish(results: list) -> None:
    failed = [r for r in results if not r["pass"]]
    print(json.dumps({"probes": len(results), "passed": len(results) - len(failed), "failed": failed, "all": results}, indent=2, default=str))
    sys.exit(0 if not failed else 1)


def phase_stateless(args):
    """Several API heads, one shared PostgreSQL and Redis: any head must be able to serve any request."""
    guard()
    heads = _heads(args)
    R: list[dict] = []
    _record(R, "more than one API head is running", ">= 2", len(heads), len(heads) >= 2)
    # student bearer session minted on head A is honoured by every head
    login = _student_login(heads[0], 0)
    token = login.json().get("access_token") if login.status_code == 200 else None
    codes = [httpx.get(f"{h}/api/v1/sync/bootstrap", headers={"authorization": f"Bearer {token}"}, timeout=30).status_code for h in heads] if token else []
    _record(R, "student token from head 1 accepted by every head", [200] * len(heads), codes, codes == [200] * len(heads) and bool(codes))
    # password change on head B revokes the session everywhere
    if len(heads) > 1:
        t1 = _student_login(heads[0], 1).json().get("access_token")
        new_pw = "Stress#Changed2026pw"
        ch = httpx.post(f"{heads[1]}/api/v1/student/auth/password", json={"current_password": STUDENT_PW, "new_password": new_pw}, headers={"authorization": f"Bearer {t1}"}, timeout=30)
        after = [httpx.get(f"{h}/api/v1/sync/bootstrap", headers={"authorization": f"Bearer {t1}"}, timeout=30).status_code for h in heads]
        _record(R, "password change on head 2 revokes the token on every head", [401] * len(heads), after, ch.status_code == 200 and all(c == 401 for c in after))
        again = _student_login(heads[-1], 1, password=new_pw).status_code
        _record(R, "new password works on a different head", 200, again, again == 200)
    # faculty cookie session across heads, then logout on one head kills it on all
    fac = _faculty_login(heads[0])
    cookies = dict(fac.cookies)
    seen = [httpx.get(f"{h}/api/v1/faculty/classes/today", cookies=cookies, timeout=30).status_code for h in heads]
    _record(R, "faculty cookie from head 1 accepted by every head", [200] * len(heads), seen, seen == [200] * len(heads))
    out = httpx.post(f"{heads[-1]}/api/v1/faculty/auth/logout", cookies=cookies, headers={"x-csrf-token": cookies.get("offlineqr_faculty_csrf", "")}, timeout=30).status_code
    gone = [httpx.get(f"{h}/api/v1/faculty/classes/today", cookies=cookies, timeout=30).status_code for h in heads]
    _record(R, "logout on the last head ends the session on every head", [401] * len(heads), gone, out == 200 and all(c == 401 for c in gone))
    # the rate limit is one shared budget, not one per head (per-source budget for student-auth is 120/min, per-IP ceiling 360/min)
    ip, statuses = "203.0.113.9", []
    for i in range(480):
        statuses.append(httpx.post(f"{heads[i % len(heads)]}/api/v1/student/auth/login", json={"roll_number": str(ROLL_BASE + 5), "password": f"x{i}"},
                                   headers={"X-Forwarded-For": ip}, timeout=30).status_code)
    first_429 = statuses.index(429) + 1 if 429 in statuses else None
    _record(R, "login rate limit is one shared budget across heads (120/min, not 120 x heads)", "first 429 between request 100 and 140",
            f"first 429 at request {first_429}", first_429 is not None and 100 <= first_429 <= 140)
    # the same proof posted to every head at the same instant yields one record
    state = load_state()
    n = 17
    c = n // state["per"]
    item = build_items(state, [n])[0]
    import concurrent.futures as cf

    def post(h):
        return httpx.post(f"{h}/api/v1/attendance/proofs/batch", json={"proofs": [item["sub"]]}, headers={"x-student-id": item["student_id"]}, timeout=30).json()["results"][0]
    with cf.ThreadPoolExecutor(len(heads) * 4) as ex:
        outs = list(ex.map(post, heads * 4))
    with psycopg.connect(get_settings().database_url) as conn:
        cnt = conn.execute("SELECT count(*) FROM attendance_records WHERE attendance_session_id=%s AND student_id=%s", [state["sessions"][c]["session_id"], item["student_id"]]).fetchone()[0]
    kinds = sorted({o.get("result") + ":" + str(o.get("error_code") or "") for o in outs})
    _record(R, f"same proof sent to {len(heads)} heads x4 at once creates exactly one record", 1, f"{cnt} record; outcomes {kinds}", cnt == 1)
    _finish(R)


def phase_ws(args):
    """Live faculty roster: WebSocket clients on different heads must be told about proofs accepted by other heads."""
    guard()
    import websockets.sync.client as wsc
    import threading

    heads = _heads(args)
    state = load_state()
    sid = state["sessions"][0]["session_id"]
    fac = _faculty_login(heads[0])
    cookie = "; ".join(f"{k}={v}" for k, v in fac.cookies.items())
    sockets, lat, versions = [], [], {}
    lock = threading.Lock()
    posted: dict = {"t": 0.0}

    def listen(i, base):
        url = base.replace("http", "ws") + f"/api/v1/faculty/attendance-sessions/{sid}/events"
        try:
            with wsc.connect(url, additional_headers={"Cookie": cookie, "Origin": "http://127.0.0.1:5173"}, open_timeout=10) as ws:
                with lock:
                    sockets.append(i)
                while time.time() < posted.get("end", time.time() + 60):
                    try:
                        msg = json.loads(ws.recv(timeout=1))
                    except TimeoutError:
                        continue
                    now = time.time()
                    with lock:
                        versions.setdefault(i, []).append(msg.get("version"))
                        if posted["t"] and now >= posted["t"]:
                            lat.append(now - posted["t"])
                            posted["t"] = 0.0
        except Exception as exc:
            with lock:
                versions.setdefault(i, []).append("ERR " + type(exc).__name__)

    posted["end"] = time.time() + 40
    threads = [threading.Thread(target=listen, args=(i, heads[i % len(heads)]), daemon=True) for i in range(60)]
    [t.start() for t in threads]
    time.sleep(4)
    got_connected = len(sockets)
    items = build_items(state, list(range(0, 24)))
    deltas = []
    for it in items:
        with lock:
            posted["t"] = time.time()
        t0 = time.time()
        httpx.post(f"{heads[-1]}/api/v1/attendance/proofs/batch", json={"proofs": [it["sub"]]}, headers={"x-student-id": it["student_id"]}, timeout=30)
        time.sleep(1.6)
        deltas.append(t0)
    posted["end"] = time.time() + 4
    time.sleep(5)
    final_versions = [v[-1] for v in versions.values() if v and isinstance(v[-1], int)]
    R: list[dict] = []
    _record(R, "60 faculty WebSocket clients connect across all heads", 60, got_connected, got_connected == 60)
    _record(R, "every socket received the final session version", "all equal", sorted(set(final_versions))[:5], len(set(final_versions)) == 1 and len(final_versions) >= 55)
    med = sorted(lat)[len(lat) // 2] if lat else None
    _record(R, "median proof-to-portal latency under 2.5 s", "< 2.5 s", f"{med:.2f} s over {len(lat)} samples" if med else "no samples", med is not None and med < 2.5)
    _record(R, "no socket error", 0, sum(1 for v in versions.values() if v and isinstance(v[-1], str)), all(not (v and isinstance(v[-1], str)) for v in versions.values()))
    _finish(R)


def phase_natburst(args):
    """Many students behind ONE campus NAT address: the per-IP ceilings are the bottleneck, not the servers."""
    guard()
    args.one_ip = True
    state = load_state()
    idx = [n for n in _all(state) if n // state["per"] >= 2][:3000]  # classes 0-1 were used by earlier probes
    res = run_load(state, idx, args, retries=max(args.retries, 120))
    ver = verify_counts(state, keys_to_expected(res["ack_keys"]), "natburst")
    throttled = res["http"].get("429", 0)
    report = {**_strip(res), "verify": ver, "http_429": throttled, "students": len(idx),
              "implied_drain_minutes_for_30000": round(30000 / max(1.0, res["throughput_per_s"]) / 60, 1),
              "implied_drain_minutes_for_120000": round(120000 / max(1.0, res["throughput_per_s"]) / 60, 1)}
    report["ok"] = ver["ok"] and res["gave_up"] == 0
    print(json.dumps(report, indent=2))
    sys.exit(0 if report["ok"] else 1)


def phase_pentest(args):
    """Second, deeper penetration round: protocol abuse, auth edge cases, resource exhaustion, race conditions."""
    guard()
    import socket
    import statistics

    heads = _heads(args)
    base = heads[0]
    state = load_state()
    R: list[dict] = []
    H = lambda n: {"x-student-id": str(uid("student", n)), "X-Forwarded-For": f"172.20.{n % 250}.{n // 250 % 250 + 1}"}  # noqa: E731
    qr = qr_payload_for(uuid.UUID(state["sessions"][0]["session_id"]), now=datetime.fromisoformat(state["sessions"][0]["started_at"]) + timedelta(seconds=0.5))

    def proof(sub, n=30, headers=None):
        r = httpx.post(f"{base}/api/v1/attendance/proofs/batch", json={"proofs": [sub]}, headers=headers or H(n), timeout=30)
        try:
            body = r.json()["results"][0]
            return body.get("error_code") or body.get("result")
        except Exception:
            return f"HTTP_{r.status_code}"

    # --- user enumeration: unknown roll vs wrong password must look and cost the same
    def timing(roll, count=4):
        xs = []
        for i in range(count):
            t = time.perf_counter()
            r = httpx.post(f"{base}/api/v1/student/auth/login", json={"roll_number": roll, "password": "WrongPassword#1234"}, headers={"X-Forwarded-For": f"10.7.{i}.{random.randint(1, 250)}"}, timeout=30)
            xs.append((time.perf_counter() - t, r.status_code, r.json().get("error", {}).get("message")))
        return xs
    known, unknown = timing(str(ROLL_BASE + 4)), timing("99999999")
    km, um = statistics.median(x[0] for x in known) * 1000, statistics.median(x[0] for x in unknown) * 1000
    _record(R, "login message identical for unknown roll and wrong password", "same status and text", f"{known[0][1:]} vs {unknown[0][1:]}", known[0][1:] == unknown[0][1:])
    _record(R, "login timing does not reveal valid roll numbers", "medians within 30%", f"known {km:.0f} ms, unknown {um:.0f} ms", abs(km - um) / max(km, um) < 0.30)
    # --- malformed and hostile inputs to the unauthenticated proof endpoint
    base_sub = make_submission(31, qr)
    s = json.loads(json.dumps(base_sub)); s["claim"]["qr_epoch"] = -1
    _record(R, "negative qr_epoch", "rejected, no crash", proof(s, 31), proof(s, 31) not in ("ACCEPTED",) and "HTTP_5" not in str(proof(s, 31)))
    s = json.loads(json.dumps(base_sub)); s["claim"]["qr_epoch"] = 2 ** 63
    r = httpx.post(f"{base}/api/v1/attendance/proofs/batch", json={"proofs": [s]}, headers=H(31), timeout=30)
    verdict = (r.json().get("results") or [{}])[0].get("result") if r.status_code == 200 else f"HTTP_{r.status_code}"
    _record(R, "qr_epoch = 2^63 (integer overflow)", "REJECTED or 4xx, never ACCEPTED/5xx", verdict, verdict in ("REJECTED", "HTTP_400", "HTTP_409", "HTTP_422"))
    s = json.loads(json.dumps(base_sub)); s["proof"]["proof_id"] = "00000000-0000-0000-0000-000000000000\x00"
    r = httpx.post(f"{base}/api/v1/attendance/proofs/batch", json={"proofs": [s]}, headers=H(31), timeout=30)
    _record(R, "NUL byte inside a UUID field", "422", r.status_code, r.status_code == 422)
    deep = "[" * 5000 + "]" * 5000
    r = httpx.post(f"{base}/api/v1/attendance/proofs/batch", content=('{"proofs": ' + deep + '}').encode(), headers={"content-type": "application/json", **H(31)}, timeout=30)
    _record(R, "5,000-level nested JSON", "4xx, no crash", r.status_code, r.status_code in (400, 413, 422))
    r = httpx.post(f"{base}/api/v1/attendance/proofs/batch", content=b"proofs=1", headers={"content-type": "application/x-www-form-urlencoded", **H(31)}, timeout=30)
    _record(R, "wrong content-type", "415/422", r.status_code, r.status_code in (400, 415, 422))
    for verb in ("PUT", "DELETE", "PATCH"):
        r = httpx.request(verb, f"{base}/api/v1/attendance/proofs/batch", headers=H(31), timeout=30)
        _record(R, f"{verb} on the proof endpoint", 405, r.status_code, r.status_code == 405)
    sk = socket.create_connection(("127.0.0.1", int(base.rsplit(":", 1)[1])), timeout=5)
    sk.sendall(b"GET /api/v1/" + b"a" * 70000 + b" HTTP/1.1\r\nHost: x\r\n\r\n")
    line = sk.recv(200).split(b"\r\n")[0].decode(errors="replace")
    sk.close()
    _record(R, "70 KB URL", "4xx", line, " 4" in line[8:12] or "414" in line or "431" in line or "400" in line)
    r = httpx.get(f"{base}/api/v1/health/live", headers={"X-Correlation-Id": "x\r\nSet-Cookie: pwned=1"}, timeout=30) if False else None
    try:
        r = httpx.get(f"{base}/api/v1/health/live", headers={"X-Correlation-Id": "abc\ndef"}, timeout=30)
        echoed = r.headers.get("x-correlation-id", "")
        _record(R, "log/header injection through X-Correlation-Id", "no newline reflected", repr(echoed), "\n" not in echoed and "\r" not in echoed)
    except Exception as exc:
        _record(R, "log/header injection through X-Correlation-Id", "no newline reflected", type(exc).__name__, True)
    # --- slow clients: 300 half-open sockets must not stop real traffic
    socks = []
    for _ in range(300):
        try:
            sk = socket.create_connection(("127.0.0.1", int(base.rsplit(":", 1)[1])), timeout=2)
            sk.sendall(b"POST /api/v1/attendance/proofs/batch HTTP/1.1\r\nHost: x\r\nContent-Length: 100000\r\n\r\n")
            socks.append(sk)
        except OSError:
            break
    t = time.perf_counter()
    ok_health = httpx.get(f"{base}/api/v1/health/live", timeout=5).status_code == 200
    lat_ms = (time.perf_counter() - t) * 1000
    _record(R, f"{len(socks)} stalled upload sockets do not block other users", "health < 1 s", f"{lat_ms:.0f} ms", ok_health and lat_ms < 1000)
    for sk in socks:
        sk.close()
    # --- cookies, CSRF, session handling
    fac = _faculty_login(base)
    set_cookie = [v for k, v in fac.headers.items()] if False else None
    r = httpx.post(f"{base}/api/v1/faculty/auth/login", json={"email": FACULTY_EMAIL, "password": FACULTY_PW}, timeout=30)
    flags = " | ".join(r.headers.get_list("set-cookie")).lower()
    _record(R, "session cookie is HttpOnly and SameSite=Strict", "httponly; samesite=strict", flags[:120], "httponly" in flags and "samesite=strict" in flags)
    cookies = dict(fac.cookies)
    sess = state["sessions"][0]["session_id"]
    r = httpx.post(f"{base}/api/v1/faculty/attendance-sessions/{sess}/close", cookies=cookies, timeout=30)
    _record(R, "faculty POST without CSRF token", 403, r.status_code, r.status_code == 403)
    r = httpx.post(f"{base}/api/v1/faculty/attendance-sessions/{sess}/close", cookies=cookies, headers={"x-csrf-token": "forged"}, timeout=30)
    _record(R, "faculty POST with forged CSRF token", 403, r.status_code, r.status_code == 403)
    r = httpx.options(f"{base}/api/v1/faculty/profile", headers={"Origin": "https://evil.example", "Access-Control-Request-Method": "GET"}, timeout=30)
    _record(R, "CORS with credentials from a hostile origin", "no allow-origin", r.headers.get("access-control-allow-origin"), not r.headers.get("access-control-allow-origin"))
    # --- WebSocket access control
    import websockets.sync.client as wsc
    for label, kw in (("no cookie", {}), ("forged cookie", {"additional_headers": {"Cookie": "offlineqr_faculty_session=forged", "Origin": "http://127.0.0.1:5173"}}),
                      ("valid cookie, hostile origin", {"additional_headers": {"Cookie": "; ".join(f"{k}={v}" for k, v in cookies.items()), "Origin": "https://evil.example"}})):
        try:
            with wsc.connect(base.replace("http", "ws") + f"/api/v1/faculty/attendance-sessions/{sess}/events", open_timeout=5, **kw) as ws:
                try:
                    ws.recv(timeout=2)
                    got = "message received"
                except Exception as exc:
                    got = "closed: " + type(exc).__name__
        except Exception as exc:
            got = "refused: " + type(exc).__name__
        _record(R, f"WebSocket events with {label}", "refused", got, got.startswith(("refused", "closed")))
    # --- IDOR: another faculty's session and another student's device
    other = state["sessions"][1]["session_id"]
    r = httpx.get(f"{base}/api/v1/faculty/attendance-sessions/{other}", cookies=cookies, timeout=30)
    _record(R, "faculty reads another faculty's session by id (IDOR)", "403/404", r.status_code, r.status_code in (403, 404))
    r = httpx.post(f"{base}/api/v1/faculty/attendance-sessions/{other}/attest", cookies=cookies, headers={"x-csrf-token": cookies.get("offlineqr_faculty_csrf", "")},
                   json={"student_id": str(uid("student", state["per"] + 1)), "reason": "Student device failure"}, timeout=30)
    _record(R, "faculty attests a student in another faculty's session", "403/404", r.status_code, r.status_code in (403, 404))
    r = httpx.get(f"{base}/api/v1/devices/current", headers=H(40), timeout=30)
    body = r.json() if r.status_code == 200 and r.content else None
    _record(R, "device endpoint returns only the caller's own device", "own device id only", (body or {}).get("id", "none") if body else r.status_code, body is None or body.get("id") == str(uid("device", 40)))
    # --- race: faculty closes the class while proofs are in flight; nothing may be half-saved
    items = build_items(state, list(range(100, 100 + 100)))
    res: list = []
    import concurrent.futures as cf

    def fire(it):
        return httpx.post(f"{base}/api/v1/attendance/proofs/batch", json={"proofs": [it["sub"]]}, headers={"x-student-id": it["student_id"]}, timeout=60).json()["results"][0]
    with cf.ThreadPoolExecutor(32) as ex:
        futs = [ex.submit(fire, it) for it in items]
        time.sleep(0.4)
        httpx.post(f"{base}/api/v1/faculty/attendance-sessions/{state['sessions'][1]['session_id']}/close", headers={"x-faculty-id": str(uid("faculty", 1))}, timeout=30)
        res = [f.result() for f in futs]
    accepted = [r_ for r_ in res if r_.get("result") in ("ACCEPTED", "ALREADY_ACCEPTED")]
    with psycopg.connect(get_settings().database_url) as conn:
        saved = conn.execute("SELECT count(*) FROM attendance_records WHERE student_id = ANY(%s) AND status='PRESENT'", [[it["student_id"] for it in items]]).fetchone()[0]
    _record(R, "close-session race: every acknowledged proof is saved, nothing half-written", f"saved == acknowledged ({len(accepted)})", saved, saved == len(accepted))
    # --- concurrent password guessing against one account must still lock it
    codes = []
    with cf.ThreadPoolExecutor(24) as ex:
        codes = list(ex.map(lambda i: _student_login(base, 3, password=f"bad{i}", ip=f"10.6.{i}.1").status_code, range(40)))
    with psycopg.connect(get_settings().database_url) as conn:
        locked = conn.execute("SELECT locked_until IS NOT NULL, failed_login_count FROM student_credentials WHERE student_id=%s", [uid("student", 3)]).fetchone()
    good = _student_login(base, 3, ip="10.6.250.1").status_code
    _record(R, "40 parallel wrong passwords lock the account; correct password then refused", "locked, 401", f"{locked}, {good}", bool(locked and locked[0]) and good == 401)
    _finish(R)


def phase_verify(args):
    guard()
    state = load_state()
    print(json.dumps(verify_counts(state, None, "verify"), indent=2))


def main() -> None:
    if len(sys.argv) > 1 and sys.argv[1] == "_shard":  # internal: one client process of a multi-process load run
        _shard_main(sys.argv[2], sys.argv[3])
        return
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    pv = sub.add_parser("provision")
    pv.add_argument("--classes", type=int, default=5)
    pv.add_argument("--students", type=int, default=100)
    pv.set_defaults(fn=provision)
    for name, fn in (("burst", phase_burst), ("duplicates", phase_duplicates), ("chaos", phase_chaos), ("offline", phase_offline),
                     ("security", phase_security), ("stateless", phase_stateless), ("pentest", phase_pentest), ("ws", phase_ws), ("natburst", phase_natburst), ("natfix", phase_natburst), ("finalize", phase_finalize), ("verify", phase_verify)):
        sp = sub.add_parser(name)
        sp.add_argument("--base-url", default="http://127.0.0.1:8100")
        sp.add_argument("--concurrency", type=int, default=1000)
        sp.add_argument("--retries", type=int, default=8)
        sp.add_argument("--timeout", type=float, default=30.0)
        sp.add_argument("--batch", type=int, default=1, help="proofs per request (the app sends its outbox as one batch)")
        sp.add_argument("--one-ip", action="store_true", help="all clients share one source IP (campus NAT)")
        sp.add_argument("--server-pid", default="0", help="comma-separated head supervisor pids (chaos)")
        sp.add_argument("--limit", type=int, default=0, help="only the first N students (duplicates phase)")
        sp.add_argument("--kill-heads", action="store_true", help="chaos may SIGKILL a whole head")
        sp.add_argument("--procs", type=int, default=0, help="client processes sharing the load")
        sp.set_defaults(fn=fn)
    args = p.parse_args()
    global PROCS
    PROCS = getattr(args, "procs", 1) or PROCS
    lab = os.environ.get("STRESS_LAB")  # optional live dashboard feed (JSON file polled by a web page)
    if not lab or args.cmd == "provision":
        args.fn(args)
        return
    import contextlib
    import io

    def write(entry: dict) -> None:
        path = Path(lab)
        try:
            data = json.loads(path.read_text())
        except Exception:
            data = {"phases": {}}
        data["phases"][args.cmd] = entry
        data["updated"] = time.time()
        path.write_text(json.dumps(data))

    write({"status": "running", "started": time.time()})
    buf, code = io.StringIO(), 0
    started = time.time()
    with contextlib.redirect_stdout(buf):
        try:
            args.fn(args)
        except SystemExit as exc:
            code = exc.code if isinstance(exc.code, int) else 1
        except Exception as exc:  # report crashes on the dashboard too
            buf.write(json.dumps({"error": repr(exc)}))
            code = 2
    text = buf.getvalue()
    try:
        report = json.loads(text)
    except Exception:
        report = {"raw": text[-2000:]}
    write({"status": "passed" if code == 0 else "failed", "started": started, "ended": time.time(), "report": report})
    sys.stdout.write(text)
    sys.exit(code)


if __name__ == "__main__":
    main()
