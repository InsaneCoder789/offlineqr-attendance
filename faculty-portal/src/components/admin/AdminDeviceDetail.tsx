"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { adminApi, type AdminDeviceDetail, type AdminDeviceHistory } from "../../admin-api";
import { DeviceVisual } from "./DeviceVisual";

function when(value?: string | null) { return value ? new Intl.DateTimeFormat("en-IN", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value)) : "Not recorded"; }

export function AdminDeviceDetail({ deviceId }: { deviceId: string }) {
  const [device, setDevice] = useState<AdminDeviceDetail | null>(null);
  const [history, setHistory] = useState<AdminDeviceHistory[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(true);

  async function load() {
    setBusy(true);
    try {
      const [nextDevice, nextHistory] = await Promise.all([adminApi.device(deviceId), adminApi.history(deviceId)]);
      setDevice(nextDevice); setHistory(nextHistory); setError(null);
    } catch (cause) { setError(cause instanceof Error ? cause.message : "Device record unavailable."); }
    finally { setBusy(false); }
  }

  useEffect(() => { void load(); }, [deviceId]);

  async function revoke() {
    const reason = window.prompt("Reason for revoking this device", "Device reported lost or compromised.");
    if (!reason || reason.trim().length < 3) return;
    try { await adminApi.revoke(deviceId, reason.trim()); await load(); }
    catch (cause) { setError(cause instanceof Error ? cause.message : "Device could not be revoked."); }
  }

  if (busy) return <main className="admin-detail"><p>Loading protected device record...</p></main>;
  if (error || !device) return <main className="admin-detail"><Link href="/admin">Back to Device Governance</Link><p className="admin-error">{error ?? "Device not found."}</p></main>;
  return <main className="admin-detail">
    <Link className="back-link" href="/admin">Back to Device Governance</Link>
    <header className="admin-detail-header"><DeviceVisual manufacturer={device.manufacturer} platform={device.platform} className="large" /><div><p className="eyeline">{device.device_reference}</p><h1>{device.manufacturer ?? device.platform} {device.device_model ?? "Attendance device"}</h1><p>{device.student_name} · {device.roll_number} · {device.section_code}</p></div><span className={`device-state ${device.status.toLowerCase()}`}>{device.status}</span></header>
    <section className="admin-detail-grid"><article className="admin-panel"><h2>Binding details</h2><Info label="Platform" value={device.platform} /><Info label="OS" value={device.os_version ?? "Not reported"} /><Info label="Physical device" value={device.is_physical_device === true ? "Declared physical" : device.is_physical_device === false ? "Rejected emulator signal" : "Not declared"} /><Info label="Integrity state" value={device.integrity_status.replaceAll("_", " ")} /><Info label="Registered" value={when(device.registered_at)} /><Info label="Last seen" value={when(device.last_seen_at)} /><Info label="Key fingerprint" value={device.key_fingerprint} mono /></article><article className="admin-panel"><h2>Risk and action</h2><p>Device facts are for institutional review only. No raw MAC address, IMEI, advertising ID, serial number, or location is stored.</p><div className="risk-list">{device.risk_flags.length ? device.risk_flags.map((flag) => <span key={flag}>{flag.replaceAll("_", " ")}</span>) : <span>NO CURRENT FLAGS</span>}</div>{device.status !== "REVOKED" ? <button className="danger" onClick={() => void revoke()}>Revoke Device Binding</button> : <p className="admin-empty">This binding was revoked {when(device.revoked_at)}.</p>}</article></section>
    <section className="admin-panel"><h2>Immutable device history</h2><p>Every enrollment, verification, switch request, decision, and revocation is retained for audit.</p><ol className="device-history">{history.length ? history.map((entry) => <li key={entry.id}><div><strong>{entry.event_type.replaceAll("_", " ")}</strong><span>{when(entry.occurred_at)} · {entry.actor_type}</span></div><code>{JSON.stringify(entry.metadata)}</code></li>) : <li>No device events were found.</li>}</ol></section>
  </main>;
}

function Info({ label, value, mono = false }: { label: string; value: string; mono?: boolean }) { return <div className="detail-info"><span>{label}</span><strong className={mono ? "mono" : ""}>{value}</strong></div>; }
