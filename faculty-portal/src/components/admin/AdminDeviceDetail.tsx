"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { AlertTriangle, ArrowLeft, Ban, Clock3, History, RefreshCw, ShieldCheck } from "lucide-react";
import { adminApi, type AdminDeviceDetail, type AdminDeviceHistory } from "@/admin-api";
import { DeviceVisual } from "./DeviceVisual";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Field, FieldDescription, FieldLabel } from "@/components/ui/field";
import { Skeleton } from "@/components/ui/skeleton";
import { Textarea } from "@/components/ui/textarea";
import { EmptyPanel, SectionHeading, StatusBadge } from "../PortalUI";

function when(value?: string | null) {
  return value ? new Intl.DateTimeFormat("en-IN", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value)) : "Not recorded";
}

export function AdminDeviceDetail({ deviceId }: { deviceId: string }) {
  const [device, setDevice] = useState<AdminDeviceDetail | null>(null);
  const [history, setHistory] = useState<AdminDeviceHistory[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(true);
  const [revokeOpen, setRevokeOpen] = useState(false);
  const [reason, setReason] = useState("Device reported lost or compromised.");

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
    if (reason.trim().length < 3) return;
    setBusy(true);
    try {
      await adminApi.revoke(deviceId, reason.trim());
      setRevokeOpen(false);
      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Device could not be revoked.");
    } finally {
      setBusy(false);
    }
  }

  if (busy && !device) return (
    <div className="flex flex-col gap-5" aria-busy="true" aria-label="Loading protected device record">
      <Skeleton className="h-9 w-40" /><Skeleton className="h-28 rounded-xl" /><div className="grid gap-5 xl:grid-cols-2"><Skeleton className="h-72 rounded-xl" /><Skeleton className="h-72 rounded-xl" /></div><Skeleton className="h-64 rounded-xl" />
    </div>
  );
  if (!device) return <><Button variant="ghost" className="w-fit" render={<Link href="/admin" />}><ArrowLeft data-icon="inline-start" />Back to governance</Button><Alert variant="destructive"><AlertTriangle /><AlertTitle>Device record unavailable</AlertTitle><AlertDescription><span>{error ?? "Device not found."}</span><Button className="mt-3 w-fit" size="sm" variant="outline" onClick={() => void load()}><RefreshCw data-icon="inline-start" />Try again</Button></AlertDescription></Alert></>;

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
      <Button variant="ghost" className="w-fit" render={<Link href="/admin" />}><ArrowLeft data-icon="inline-start" />Back to governance</Button>
      <Card>
        <div className="flex flex-col gap-4 p-4 sm:flex-row sm:items-center sm:p-5">
          <DeviceVisual manufacturer={device.manufacturer} platform={device.platform} className="size-14" />
          <div className="min-w-0 flex-1">
            <p className="break-all font-mono text-xs text-primary">{device.device_reference}</p>
            <h2 className="mt-1 break-words text-2xl font-semibold leading-tight">{device.manufacturer ?? device.platform} {device.device_model ?? "Attendance device"}</h2>
            <p className="mt-1 break-words text-sm text-muted-foreground">{device.student_name} · {device.roll_number} · Section {device.section_code}</p>
          </div>
          <StatusBadge tone={device.status === "ACTIVE" ? "success" : device.status === "REVOKED" ? "error" : "warning"}>{device.status}</StatusBadge>
        </div>
        <dl className="grid grid-cols-2 gap-px border-t bg-border text-sm md:grid-cols-4">
          {[["Integrity", device.integrity_status.replaceAll("_", " ")], ["Platform", device.platform], ["Last seen", when(device.last_seen_at)], ["Risk flags", String(device.risk_flags.length)]].map(([label, value]) => <div className="min-w-0 bg-card px-4 py-3" key={label}><dt className="text-xs text-muted-foreground">{label}</dt><dd className="mt-1 break-words font-medium">{value}</dd></div>)}
        </dl>
      </Card>
      {error ? <Alert variant="destructive"><AlertTriangle /><AlertTitle>Action could not be completed</AlertTitle><AlertDescription><span>{error}</span><Button className="mt-3 w-fit" size="sm" variant="outline" disabled={busy} onClick={() => void load()}><RefreshCw data-icon="inline-start" />Reload record</Button></AlertDescription></Alert> : null}

      <section className="grid gap-5 xl:grid-cols-2">
        <Card>
          <CardHeader><div className="mb-3 flex items-center gap-3"><DeviceVisual manufacturer={device.manufacturer} platform={device.platform} className="size-14" /><div><CardTitle>Binding details</CardTitle><CardDescription>Server-verified device record</CardDescription></div></div></CardHeader>
          <CardContent className="flex flex-col gap-0">
            {details.map(([label, value]) => <Info key={label} label={label} value={value} mono={label === "Key fingerprint"} />)}
          </CardContent>
        </Card>
        <Card>
          <CardHeader><CardTitle>Risk and action</CardTitle><CardDescription>Device facts support institutional review without collecting raw hardware identifiers.</CardDescription></CardHeader>
          <CardContent className="flex flex-col gap-5">
            <Alert><ShieldCheck /><AlertTitle>Privacy-preserving evidence</AlertTitle><AlertDescription>No MAC address, IMEI, advertising ID, serial number, or precise location is stored.</AlertDescription></Alert>
            <div className="flex flex-wrap gap-2">{device.risk_flags.length ? device.risk_flags.map((flag) => <StatusBadge key={flag} tone="warning">{flag.replaceAll("_", " ")}</StatusBadge>) : <StatusBadge tone="success">No current flags</StatusBadge>}</div>
            <div className="rounded-lg border border-destructive/30 p-4">
              <p className="text-sm font-medium">Revoke binding</p>
              {device.status !== "REVOKED" ? <>
                <p className="mt-1 text-sm text-muted-foreground">The student cannot submit attendance from this device until a controlled replacement is approved.</p>
                <Button variant="destructive" className="mt-3 min-h-11 w-full sm:min-h-0 sm:w-fit" onClick={() => setRevokeOpen(true)}><Ban data-icon="inline-start" />Revoke device binding</Button>
              </> : <p className="mt-1 text-sm text-muted-foreground">This binding was revoked {when(device.revoked_at)}.</p>}
            </div>
          </CardContent>
        </Card>
      </section>

      <Card>
        <SectionHeading title="Immutable device history" description="Enrollment, verification, switching, decisions, and revocation events retained for audit." action={<StatusBadge icon={History}>{history.length} events</StatusBadge>} />
        {history.length === 0 ? <EmptyPanel icon={History} title="No device events" description="No audit events were returned for this binding." className="m-5" /> : (
          <ol className="relative px-4 py-4 sm:px-5">
            <span className="absolute bottom-8 left-[2.15rem] top-8 w-px bg-border sm:left-[2.4rem]" aria-hidden="true" />
            {history.map((entry) => (
              <li className="relative grid grid-cols-[auto_minmax(0,1fr)] gap-3 py-3" key={entry.id}>
                <span className="relative z-10 flex size-8 items-center justify-center rounded-full border bg-card text-primary"><Clock3 className="size-4" /></span>
                <div className="min-w-0">
                  <strong className="block text-sm">{entry.event_type.replaceAll("_", " ")}</strong>
                  <span className="mt-0.5 block text-xs text-muted-foreground">{when(entry.occurred_at)} · {entry.actor_type}</span>
                  <code className="mt-2 block max-w-full overflow-x-auto rounded-lg bg-muted px-3 py-2 text-[11px] leading-5 text-muted-foreground">{JSON.stringify(entry.metadata)}</code>
                </div>
              </li>
            ))}
          </ol>
        )}
      </Card>

      <Dialog open={revokeOpen} onOpenChange={setRevokeOpen}>
        <DialogContent>
          <DialogHeader><DialogTitle>Revoke device binding</DialogTitle><DialogDescription>This immediately prevents the device from submitting new attendance proofs.</DialogDescription></DialogHeader>
          <Field><FieldLabel htmlFor="revoke-reason">Revocation reason</FieldLabel><Textarea id="revoke-reason" value={reason} onChange={(event) => setReason(event.target.value)} rows={4} /><FieldDescription>The reason is retained in the immutable device history.</FieldDescription></Field>
          <p className="text-sm text-muted-foreground">Revoking {device.manufacturer ?? device.platform} {device.device_model ?? "device"} for {device.student_name} ({device.roll_number}).</p>
          <DialogFooter><Button variant="outline" disabled={busy} onClick={() => setRevokeOpen(false)}>Cancel</Button><Button variant="destructive" disabled={busy || reason.trim().length < 3} onClick={() => void revoke()}><Ban data-icon="inline-start" />{busy ? "Revoking" : "Confirm revocation"}</Button></DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}

function Info({ label, value, mono = false }: { label: string; value: string; mono?: boolean }) {
  return <div className="grid gap-1 border-t py-3 first:border-t-0 sm:grid-cols-[10rem_minmax(0,1fr)]"><span className="text-xs text-muted-foreground">{label}</span><strong className={mono ? "break-all font-mono text-xs font-medium" : "break-words text-sm font-medium"}>{value}</strong></div>;
}
