"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { adminApi, type AdminDevice, type AdminStats, type ReplacementRequest } from "../../admin-api";
import { DeviceVisual } from "./DeviceVisual";

const sessionKey = "offlineqr.ict.approval-key";
const operatorKey = "offlineqr.ict.operator";

function dateTime(value?: string | null) {
  return value ? new Intl.DateTimeFormat("en-IN", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value)) : "Not recorded";
}

export function AdminDeviceConsole() {
  const [key, setKey] = useState("");
  const [operator, setOperator] = useState("ict-admin");
  const [ready, setReady] = useState(false);
  const [stats, setStats] = useState<AdminStats | null>(null);
  const [devices, setDevices] = useState<AdminDevice[]>([]);
  const [replacements, setReplacements] = useState<ReplacementRequest[]>([]);
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    const storedKey = sessionStorage.getItem(sessionKey);
    const storedOperator = sessionStorage.getItem(operatorKey);
    if (storedKey) {
      setKey(storedKey);
      setReady(true);
    }
    if (storedOperator) setOperator(storedOperator);
  }, []);

  async function load() {
    if (!key) return;
    setLoading(true);
    setError(null);
    try {
      const [nextStats, nextDevices, nextReplacements] = await Promise.all([
        adminApi.stats(key, operator),
        adminApi.devices(key, operator, query, status),
        adminApi.replacements(key, operator),
      ]);
      setStats(nextStats);
      setDevices(nextDevices);
      setReplacements(nextReplacements);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not load device governance data.");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    if (ready) void load();
  // Initial console load deliberately runs only after a session credential exists.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ready]);

  function beginSession(event: React.FormEvent) {
    event.preventDefault();
    sessionStorage.setItem(sessionKey, key);
    sessionStorage.setItem(operatorKey, operator);
    setReady(true);
  }

  async function decide(request: ReplacementRequest, action: "approve" | "reject") {
    const note = window.prompt(action === "approve" ? "Approval note" : "Rejection reason", "Identity and device profile reviewed.");
    if (!note || note.trim().length < 3) return;
    try {
      await (action === "approve" ? adminApi.approve(key, operator, request.id, note.trim()) : adminApi.reject(key, operator, request.id, note.trim()));
      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Decision could not be recorded.");
    }
  }

  if (!ready) {
    return (
      <main className="admin-login-page">
        <form className="admin-login-card" onSubmit={beginSession}>
          <p className="eyeline">Institutional control centre</p>
          <h1>Device Governance</h1>
          <p>Review device binding, approve switches, revoke compromised devices, and preserve every decision as an audit event.</p>
          <label>ICT operator<input value={operator} onChange={(event) => setOperator(event.target.value)} required /></label>
          <label>ICT approval credential<input value={key} onChange={(event) => setKey(event.target.value)} type="password" autoComplete="off" required /></label>
          <button type="submit">Open Device Console</button>
          <small>The credential is held only for this browser session and is never written into the portal build.</small>
        </form>
      </main>
    );
  }

  return (
    <main className="admin-console">
      <header className="admin-header">
        <div><p className="eyeline">Institutional control centre</p><h1>Device Governance</h1><p>One student, one active credential, every switch reviewable.</p></div>
        <div className="admin-header-actions"><span className="admin-operator">ICT: {operator}</span><button className="secondary" onClick={() => void load()} disabled={loading}>{loading ? "Refreshing" : "Refresh"}</button></div>
      </header>
      {error ? <p className="admin-error" role="alert">{error}</p> : null}
      <section className="admin-stats" aria-label="Device governance summary">
        <Stat label="Registered devices" value={stats?.total_devices ?? "-"} />
        <Stat label="Active bindings" value={stats?.active_devices ?? "-"} tone="success" />
        <Stat label="Pending switches" value={stats?.pending_replacements ?? "-"} tone="warning" />
        <Stat label="Manual review" value={stats?.review_required ?? "-"} tone="danger" />
        <Stat label="Revoked devices" value={stats?.revoked_devices ?? "-"} />
      </section>
      <section className="admin-panel">
        <div className="admin-panel-heading"><div><h2>Replacement approvals</h2><p>New devices remain inactive until an ICT decision is recorded.</p></div></div>
        {replacements.length === 0 ? <p className="admin-empty">No replacement requests require review.</p> : <div className="replacement-list">{replacements.map((request) => <article className="replacement-row" key={request.id}><DeviceVisual manufacturer={request.new_manufacturer} platform={request.new_platform} /><div><strong>{request.student_name} <span>{request.roll_number}</span></strong><p>{request.old_manufacturer ?? request.old_platform} {request.old_model ?? "device"} to {request.new_manufacturer ?? request.new_platform} {request.new_model ?? "device"}</p><small>{request.reason} · requested {dateTime(request.requested_at)}</small></div><span className="risk-chip">{request.new_integrity_status.replaceAll("_", " ")}</span><div className="decision-actions"><button onClick={() => void decide(request, "approve")}>Approve</button><button className="danger" onClick={() => void decide(request, "reject")}>Reject</button></div></article>)}</div>}
      </section>
      <section className="admin-panel">
        <div className="admin-panel-heading"><div><h2>Registered device inventory</h2><p>Only non-sensitive, reviewable device facts are retained. Hardware identifiers are not collected.</p></div><div className="admin-filters"><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search roll, student, or key fingerprint" /><select value={status} onChange={(event) => setStatus(event.target.value)}><option value="">All states</option><option value="ACTIVE">Active</option><option value="PENDING">Pending</option><option value="REVOKED">Revoked</option></select><button onClick={() => void load()}>Apply</button></div></div>
        <div className="device-grid">{devices.map((device) => <Link className="device-card" href={`/admin/devices/${device.id}`} key={device.id}><div className="device-card-top"><DeviceVisual manufacturer={device.manufacturer} platform={device.platform} /><span className={`device-state ${device.status.toLowerCase()}`}>{device.status}</span></div><p className="device-reference">{device.device_reference}</p><h3>{device.manufacturer ?? device.platform} {device.device_model ?? "Attendance device"}</h3><p>{device.student_name} · {device.roll_number}</p><dl><div><dt>Section</dt><dd>{device.section_code}</dd></div><div><dt>Integrity</dt><dd>{device.integrity_status.replaceAll("_", " ")}</dd></div><div><dt>Last seen</dt><dd>{dateTime(device.last_seen_at)}</dd></div></dl>{device.risk_flags.length ? <div className="risk-list">{device.risk_flags.map((flag) => <span key={flag}>{flag.replaceAll("_", " ")}</span>)}</div> : null}</Link>)}</div>
      </section>
    </main>
  );
}

function Stat({ label, value, tone = "" }: { label: string; value: string | number; tone?: string }) { return <article className={`admin-stat ${tone}`}><span>{label}</span><strong>{value}</strong></article>; }
