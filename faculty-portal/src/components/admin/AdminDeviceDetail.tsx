"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { ArrowLeft, Ban, Clock3, Flag, History, ShieldCheck } from "lucide-react";
import { adminApi, type AdminDeviceDetail, type AdminDeviceHistory } from "@/admin-api";
import { DeviceVisual } from "./DeviceVisual";
import { StateCard, dateTime as when, isForbidden, useOnline } from "./AdminStates";
import { Badge } from "@/components/ui/badge";
import { Button, buttonVariants } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Field, FieldDescription, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Textarea } from "@/components/ui/textarea";
import { StatusBadge } from "../PortalUI";
import styles from "../dark-command.module.css";
import { cn } from "@/lib/utils";

const CONFIRM_WORD = "REVOKE";

export function AdminDeviceDetail({ deviceId }: { deviceId: string }) {
  const [device, setDevice] = useState<AdminDeviceDetail | null>(null);
  const [history, setHistory] = useState<AdminDeviceHistory[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(true);
  const [revokeOpen, setRevokeOpen] = useState(false);
  const [reason, setReason] = useState("Device reported lost or compromised.");
  const [typed, setTyped] = useState("");
  const online = useOnline();

  async function load() {
    setBusy(true);
    try {
      const [nextDevice, nextHistory] = await Promise.all([adminApi.device(deviceId), adminApi.history(deviceId)]);
      setDevice(nextDevice);
      setHistory(nextHistory);
      setError(null);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Device record unavailable.");
    } finally {
      setBusy(false);
    }
  }

  useEffect(() => { void load(); /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [deviceId]);

  async function revoke() {
    if (busy || !online || reason.trim().length < 3 || typed.trim().toUpperCase() !== CONFIRM_WORD) return;
    setError(null);
    setBusy(true);
    try {
      await adminApi.revoke(deviceId, reason.trim());
      setRevokeOpen(false);
      setTyped("");
      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Device could not be revoked.");
    } finally {
      setBusy(false);
    }
  }

  const back = <Link href="/admin" className={cn(buttonVariants({ variant: "ghost" }), "w-fit")}><ArrowLeft data-icon="inline-start" />Back to governance</Link>;

  if (busy && !device) return (
    <div className="flex flex-col gap-5" aria-busy="true" aria-label="Loading protected device record">
      <Skeleton className="h-9 w-40" /><Skeleton className="h-44 rounded-3xl" /><div className="grid gap-5 xl:grid-cols-2"><Skeleton className="h-72 rounded-3xl" /><Skeleton className="h-72 rounded-3xl" /></div><Skeleton className="h-64 rounded-3xl" />
    </div>
  );
  if (!device) return <>{back}<StateCard kind={!online ? "offline" : isForbidden(error) ? "forbidden" : "error"} message={error ?? "Device not found."} onRetry={() => void load()} busy={busy} /></>;

  const tone = device.status === "ACTIVE" ? "success" : device.status === "REVOKED" ? "error" : "warning";
  const details = [
    ["Platform", device.platform],
    ["Operating system", device.os_version ?? "Not reported"],
    ["Physical-device signal", device.is_physical_device === true ? "Declared physical" : device.is_physical_device === false ? "Emulator signal rejected" : "Not declared"],
    ["Integrity state", device.integrity_status.replaceAll("_", " ")],
    ["Registered", when(device.registered_at)],
    ["Last seen", when(device.last_seen_at)],
    ["Key fingerprint", device.key_fingerprint],
  ];

  return (
    <>
      {back}
      <section className="overflow-hidden rounded-lg border bg-card">
        <div className="silk-surface flex flex-col gap-5 p-5 sm:flex-row sm:items-center sm:p-7">
          <div className="flex size-16 shrink-0 items-center justify-center rounded-lg bg-muted">
            <DeviceVisual manufacturer={device.manufacturer} platform={device.platform} className="size-16 rounded-full" />
          </div>
          <div className="min-w-0 flex-1">
            <p className="break-all font-mono text-xs text-primary">{device.device_reference}</p>
            <h2 className="mt-1 break-words text-fluid-2xl font-bold leading-tight tracking-tight">{device.manufacturer ?? device.platform} {device.device_model ?? "Attendance device"}</h2>
            <p className="mt-1 break-words text-sm text-muted-foreground">{device.student_name} · {device.roll_number} · Section {device.section_code}</p>
          </div>
          <StatusBadge tone={tone}>{device.status}</StatusBadge>
        </div>
        <dl className="grid grid-cols-2 gap-px border-t bg-border text-sm md:grid-cols-4">
          {[["Integrity", device.integrity_status.replaceAll("_", " ")], ["Platform", device.platform], ["Last seen", when(device.last_seen_at)], ["Risk flags", String(device.risk_flags.length)]].map(([label, value]) => <div className="min-w-0 bg-card px-4 py-3" key={label}><dt className="text-xs text-muted-foreground">{label}</dt><dd className={cn("mt-1 break-words font-semibold", label === "Risk flags" && device.risk_flags.length > 0 && styles.glowWarn)}>{value}</dd></div>)}
        </dl>
      </section>
      {error ? <StateCard kind="error" message={error} onRetry={() => void load()} busy={busy} /> : null}

      <section className="grid grid-cols-1 gap-5 xl:grid-cols-2">
        <div className={cn(styles.glass, "rounded-3xl p-5 sm:p-7")}>
          <h3 className="text-lg font-semibold tracking-tight">Binding details</h3>
          <p className="mb-4 text-sm text-muted-foreground">Server-verified device record</p>
          <dl className="grid sm:grid-cols-2">
            {details.map(([label, value]) => {
              const wide = label === "Key fingerprint";
              return <div key={label} className={cn("min-w-0 border-t py-3 sm:pr-4", wide && "sm:col-span-2")}><dt className="text-xs text-muted-foreground">{label}</dt><dd className={cn("mt-1 font-medium", wide ? "break-all font-mono text-xs" : "break-words text-sm")}>{value}</dd></div>;
            })}
          </dl>
        </div>
        <div className="flex min-w-0 flex-col gap-5">
          <div className={cn(styles.glass, "rounded-3xl p-5 sm:p-7")}>
            <h3 className="text-lg font-semibold tracking-tight">Risk flags</h3>
            <p className="mb-4 text-sm text-muted-foreground">Device facts support institutional review without collecting raw hardware identifiers.</p>
            <div className="flex flex-wrap gap-2">{device.risk_flags.length ? device.risk_flags.map((flag) => <Badge key={flag} variant="warning" className="h-auto min-w-0 max-w-full whitespace-normal [overflow-wrap:anywhere]"><Flag className="shrink-0" data-icon="inline-start" aria-hidden="true" /><span className="min-w-0">{flag.replaceAll("_", " ")}</span></Badge>) : <StatusBadge tone="success" icon={ShieldCheck}>No current flags</StatusBadge>}</div>
            <p className="mt-4 flex items-start gap-2 text-xs text-muted-foreground"><ShieldCheck className="mt-0.5 size-4 shrink-0 text-primary" aria-hidden="true" /><span><strong className="text-foreground">Privacy-preserving evidence.</strong> No MAC address, IMEI, advertising ID, serial number, or precise location is stored.</span></p>
          </div>
          <div className={cn(styles.glassDanger, "rounded-3xl p-5 sm:p-7")}>
            <p className="text-lg font-semibold tracking-tight text-destructive">Revoke binding</p>
            {device.status !== "REVOKED" ? <>
              <p className="mt-1 text-sm text-muted-foreground">The student cannot submit attendance from this device until a controlled replacement is approved.</p>
              <Button variant="destructive" className="mt-4 min-h-11 w-full sm:w-fit" disabled={busy || !online} onClick={() => { setError(null); setTyped(""); setRevokeOpen(true); }}><Ban data-icon="inline-start" />Revoke device binding</Button>
            </> : <p className="mt-1 text-sm text-muted-foreground">This binding was revoked {when(device.revoked_at)}.</p>}
          </div>
        </div>
      </section>

      <section className={cn(styles.glass, "rounded-3xl p-5 sm:p-7")}>
        <div className="mb-5 flex flex-wrap items-start justify-between gap-2">
          <div><h3 className="text-lg font-semibold tracking-tight">Immutable device history</h3><p className="text-sm text-muted-foreground">Enrollment, verification, switching, decisions, and revocation events retained for audit.</p></div>
          <StatusBadge icon={History}>{history.length} events</StatusBadge>
        </div>
        {history.length === 0 ? (
          <div className="flex flex-col items-center gap-2 py-10 text-center"><History className="size-6 text-muted-foreground" aria-hidden="true" /><strong>No device events</strong><p className="text-sm text-muted-foreground">No audit events were returned for this binding.</p></div>
        ) : (
          <ol className="relative">
            <span className="absolute bottom-4 left-4 top-4 w-px bg-gradient-to-b from-primary/60 via-border to-transparent" aria-hidden="true" />
            {history.map((entry) => (
              <li className="relative grid grid-cols-[auto_minmax(0,1fr)] gap-3 py-3" key={entry.id}>
                <span className="relative z-10 flex size-8 items-center justify-center rounded-full border border-primary/40 bg-card text-primary"><Clock3 className="size-4" /></span>
                <div className="min-w-0">
                  <strong className="block text-sm">{entry.event_type.replaceAll("_", " ")}</strong>
                  <span className="mt-0.5 block text-xs text-muted-foreground">{when(entry.occurred_at)} · {entry.actor_type}</span>
                  <code className="mt-2 block max-w-full overflow-x-auto rounded-xl bg-background/60 px-3 py-2 text-[11px] leading-5 text-muted-foreground">{JSON.stringify(entry.metadata)}</code>
                </div>
              </li>
            ))}
          </ol>
        )}
      </section>

      <Dialog open={revokeOpen} onOpenChange={setRevokeOpen}>
        <DialogContent>
          <DialogHeader><DialogTitle>Revoke device binding</DialogTitle><DialogDescription>This immediately prevents the device from submitting new attendance proofs.</DialogDescription></DialogHeader>
          <Field><FieldLabel htmlFor="revoke-reason">Revocation reason</FieldLabel><Textarea id="revoke-reason" value={reason} onChange={(event) => setReason(event.target.value)} rows={4} /><FieldDescription>The reason is retained in the immutable device history.</FieldDescription></Field>
          <Field><FieldLabel htmlFor="revoke-confirm">Type {CONFIRM_WORD} to confirm</FieldLabel><Input id="revoke-confirm" value={typed} onChange={(event) => setTyped(event.target.value)} autoComplete="off" autoCapitalize="characters" placeholder={CONFIRM_WORD} /></Field>
          <p className="text-sm text-muted-foreground">Revoking {device.manufacturer ?? device.platform} {device.device_model ?? "device"} for {device.student_name} ({device.roll_number}).</p>
          {error ? <p className="text-sm text-destructive" role="alert">{error}</p> : null}
          <DialogFooter><Button variant="outline" disabled={busy} onClick={() => setRevokeOpen(false)}>Cancel</Button><Button variant="destructive" disabled={busy || !online || reason.trim().length < 3 || typed.trim().toUpperCase() !== CONFIRM_WORD} onClick={() => void revoke()}><Ban data-icon="inline-start" />{busy ? "Revoking" : "Confirm revocation"}</Button></DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
