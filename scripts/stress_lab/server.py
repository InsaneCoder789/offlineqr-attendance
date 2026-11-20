#!/usr/bin/env python3
"""Live feed for the Stress HUD: serves index.html plus /live, /checklist and /status.json.

Read-only against the scratch database (offlineqr_stress). Run:  python scripts/stress_lab/server.py
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import psycopg

HERE = Path(__file__).resolve().parent
STATUS = Path(os.environ.get("STRESS_LAB", "/private/tmp/claude-501/stresslab/status.json"))
CHECKLIST = HERE.parents[1] / "docs" / "BACKEND_TEST_CHECKLIST.md"
DB = os.environ.get("STRESS_DB", "postgresql://localhost/offlineqr_stress")
API = os.environ.get("STRESS_API", "http://127.0.0.1:8100")
PIDFILE = Path("/tmp/stress_server.pid")
HEADS = Path("/tmp/stress_heads.json")
REDIS_PORT = int(os.environ.get("STRESS_REDIS_PORT", "6390"))
PORT = int(os.environ.get("STRESS_HUD_PORT", "8802"))


def live() -> dict:
    out: dict = {"t": time.time(), "load": os.getloadavg(), "db": None, "api": {"up": False}, "workers": [], "classes": []}
    try:
        with psycopg.connect(DB, connect_timeout=1, autocommit=True) as c:
            present, absent = c.execute(
                "SELECT count(*) FILTER (WHERE status='PRESENT'), count(*) FILTER (WHERE status='ABSENT') FROM attendance_records").fetchone()
            verified = c.execute("SELECT count(*) FROM attendance_proofs WHERE sync_state='SERVER_VERIFIED'").fetchone()[0]
            claims = c.execute("SELECT count(*) FROM attendance_claims").fetchone()[0]
            enrolled = c.execute("SELECT count(*) FROM enrollments e JOIN course_offerings o ON o.id=e.course_offering_id WHERE o.section_id IN (SELECT id FROM sections WHERE code LIKE 'STR-%')").fetchone()[0]
            conns = c.execute("SELECT count(*), count(*) FILTER (WHERE state='active') FROM pg_stat_activity WHERE datname=current_database()").fetchone()
            sessions = c.execute(
                """SELECT s.id, count(ar.*) FILTER (WHERE ar.status='PRESENT'),
                          (SELECT count(*) FROM enrollments e WHERE e.course_offering_id=s.course_offering_id)
                   FROM attendance_sessions s LEFT JOIN attendance_records ar ON ar.attendance_session_id=s.id
                   WHERE s.course_offering_id IN (SELECT o.id FROM course_offerings o JOIN sections sec ON sec.id=o.section_id WHERE sec.code LIKE 'STR-%%')
                   GROUP BY s.id, s.course_offering_id, s.started_at ORDER BY s.started_at, s.id""").fetchall()
            events = c.execute("SELECT event_type, count(*) FROM audit_logs WHERE created_at > now() - interval '60 seconds' GROUP BY 1 ORDER BY 2 DESC LIMIT 6").fetchall()
        out["db"] = {"present": present, "absent": absent, "verified": verified, "claims": claims, "enrolled": enrolled,
                     "conns": conns[0], "active": conns[1], "sessions": len(sessions), "events": events}
        out["classes"] = [[int(p), int(r)] for _id, p, r in sessions][:600]
    except Exception:
        pass
    heads = []
    try:
        cfg = json.loads(HEADS.read_text()) if HEADS.exists() else {"pids": [int(PIDFILE.read_text())], "urls": [API]}
    except Exception:
        cfg = {"pids": [], "urls": []}
    try:
        ps = [line.split()[:4] for line in subprocess.run(["ps", "-axo", "pid=,ppid=,pcpu=,rss="], capture_output=True, text=True).stdout.splitlines()]
    except Exception:
        ps = []
    for i, (pid, url) in enumerate(zip(cfg["pids"], cfg["urls"])):
        head = {"url": url, "pid": pid, "up": False, "ms": None, "workers": []}
        try:
            t = time.perf_counter()
            urllib.request.urlopen(f"{url}/api/v1/health/live", timeout=1).read()
            head.update(up=True, ms=round((time.perf_counter() - t) * 1000, 1))
        except Exception:
            pass
        for p, pp, cpu, rss in ps:
            if int(pp) == pid:
                head["workers"].append({"pid": int(p), "cpu": float(cpu), "mb": round(int(rss) / 1024, 1)})
        heads.append(head)
        out["workers"] += [{**w, "head": i} for w in head["workers"]]
    out["heads"] = heads
    out["api"] = {"up": any(h["up"] for h in heads), "ms": min([h["ms"] for h in heads if h["up"]] or [0]), "heads_up": sum(h["up"] for h in heads)}
    try:
        import redis as _redis

        r = _redis.Redis(port=REDIS_PORT, socket_timeout=0.5)
        info = r.info()
        out["redis"] = {"up": True, "ops": info.get("instantaneous_ops_per_sec"), "clients": info.get("connected_clients"), "mb": round(info.get("used_memory", 0) / 1048576, 1), "keys": r.dbsize()}
    except Exception:
        out["redis"] = {"up": False}
    log: list[str] = []
    for f in sorted(Path("/tmp").glob("suite_*.log"), key=lambda p: p.stat().st_mtime)[-1:]:
        log += f.read_text().splitlines()[-12:]
    out["log"] = log
    return out


def checklist() -> list[dict]:
    sections: list[dict] = []
    cur = None
    for line in CHECKLIST.read_text().splitlines():
        m = re.match(r"## (.+)", line)
        if m:
            cur = {"title": m.group(1), "items": []}
            sections.append(cur)
            continue
        m = re.match(r"- \[( |x|~)\] (.+)", line)
        if m and cur is not None:
            cur["items"].append({"s": {"x": "done", "~": "part", " ": "todo"}[m.group(1)], "t": m.group(2)})
    return [s for s in sections if s["items"]]


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):  # quiet
        pass

    def send(self, body: bytes, ctype: str) -> None:
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):  # noqa: N802
        path = self.path.split("?")[0]
        try:
            if path == "/live":
                self.send(json.dumps(live()).encode(), "application/json")
            elif path == "/checklist":
                self.send(json.dumps(checklist()).encode(), "application/json")
            elif path == "/status.json":
                self.send(STATUS.read_bytes() if STATUS.exists() else b'{"phases":{}}', "application/json")
            elif path in ("/", "/index.html"):
                self.send((HERE / "index.html").read_bytes(), "text/html; charset=utf-8")
            else:
                self.send_error(404)
        except Exception as exc:
            self.send_error(500, str(exc))


if __name__ == "__main__":
    print(f"Stress HUD on http://127.0.0.1:{PORT}")
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
