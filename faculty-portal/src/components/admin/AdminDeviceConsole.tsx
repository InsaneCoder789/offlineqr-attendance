"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import QRCode from "qrcode";
import { AlertTriangle, Check, ChevronRight, History, RefreshCw, Search, ShieldCheck, Smartphone, UserRoundCheck, X } from "lucide-react";
import { adminApi, type AdminDevice, type AdminStats, type DeviceActivationQr, type ReplacementRequest } from "@/admin-api";
import { DeviceVisual } from "./DeviceVisual";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Field, FieldDescription, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectGroup, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { MetricStrip, PageIntro, SectionHeading, StatusBadge } from "../PortalUI";

function dateTime(value?: string | null) {
  return value ? new Intl.DateTimeFormat("en-IN", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value)) : "Not recorded";
}

type Decision = { request: ReplacementRequest; action: "approve" | "reject" } | null;

export function AdminDeviceConsole() {
  const [stats, setStats] = useState<AdminStats | null>(null);
  const [devices, setDevices] = useState<AdminDevice[]>([]);
  const [replacements, setReplacements] = useState<ReplacementRequest[]>([]);
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState("all");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [activation, setActivation] = useState<DeviceActivationQr | null>(null);
  const [activationImage, setActivationImage] = useState("");
  const [decision, setDecision] = useState<Decision>(null);
  const [decisionNote, setDecisionNote] = useState("Identity and device profile reviewed.");

  async function load() {
    setLoading(true);
    setError(null);
    try {
      const [nextStats, nextDevices, nextReplacements] = await Promise.all([
        adminApi.stats(), adminApi.devices(query, status === "all" ? "" : status), adminApi.replacements(),
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

  useEffect(() => { void load(); /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, []);

  async function showActivation(requestId: string) {
    const nextActivation = await adminApi.activationQr(requestId);
    setActivation(nextActivation);
    setActivationImage(await QRCode.toDataURL(nextActivation.qr_payload, { width: 520, margin: 2, errorCorrectionLevel: "M" }));
  }

  async function submitDecision() {
    if (!decision || decisionNote.trim().length < 3) return;
    setLoading(true);
    try {
      if (decision.action === "approve") {
        await adminApi.approve(decision.request.id, decisionNote.trim());
        await showActivation(decision.request.id);
      } else {
        await adminApi.reject(decision.request.id, decisionNote.trim());
      }
      setDecision(null);
      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Decision could not be recorded.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <>
      <PageIntro
        eyebrow="ICT administration"
        title="Device governance"
        description="Review attendance-device bindings, approve controlled replacements, and inspect immutable device history."
        actions={<Button variant="outline" disabled={loading} onClick={() => void load()}><RefreshCw data-icon="inline-start" className={loading ? "animate-spin" : undefined} />Refresh data</Button>}
      />
      {error ? <Alert variant="destructive"><AlertTriangle /><AlertTitle>Governance service unavailable</AlertTitle><AlertDescription>{error}</AlertDescription></Alert> : null}
      <MetricStrip className="xl:grid-cols-5" metrics={[
        { label: "Registered devices", value: stats?.total_devices ?? "-", icon: Smartphone },
        { label: "Active bindings", value: stats?.active_devices ?? "-", icon: ShieldCheck },
        { label: "Pending switches", value: stats?.pending_replacements ?? "-", icon: History },
        { label: "Manual review", value: stats?.review_required ?? "-", icon: AlertTriangle },
        { label: "Revoked", value: stats?.revoked_devices ?? "-", icon: X },
      ]} />

      <Card>
        <SectionHeading title="Replacement approvals" description="A new device remains inactive until an ICT decision is recorded." action={<StatusBadge tone={replacements.length ? "warning" : "success"}>{replacements.length} pending</StatusBadge>} />
        {replacements.length === 0 ? <p className="px-5 py-10 text-center text-sm text-muted-foreground">No replacement requests require review.</p> : (
          <div className="divide-y">
            {replacements.map((request) => (
              <article className="grid gap-4 px-5 py-4 lg:grid-cols-[auto_minmax(0,1fr)_auto_auto] lg:items-center" key={request.id}>
                <DeviceVisual manufacturer={request.new_manufacturer} platform={request.new_platform} />
                <div className="min-w-0">
                  <div className="flex flex-wrap items-center gap-2"><strong className="truncate text-sm">{request.student_name}</strong><span className="font-mono text-xs text-muted-foreground">{request.roll_number}</span></div>
                  <p className="mt-1 text-sm text-muted-foreground">{request.old_manufacturer ?? request.old_platform} {request.old_model ?? "device"} → {request.new_manufacturer ?? request.new_platform} {request.new_model ?? "device"}</p>
                  <p className="mt-1 text-xs text-muted-foreground">{request.reason} · requested {dateTime(request.requested_at)}</p>
                </div>
                <StatusBadge tone={request.new_integrity_status.includes("FAIL") ? "error" : "neutral"}>{request.new_integrity_status.replaceAll("_", " ")}</StatusBadge>
                <div className="flex flex-wrap gap-2">
                  {request.status === "APPROVED" ? <Button size="sm" onClick={() => void showActivation(request.id).catch((cause: unknown) => setError(cause instanceof Error ? cause.message : "Could not create activation QR."))}>Show activation QR</Button> : <>
                    <Button size="sm" onClick={() => { setDecision({ request, action: "approve" }); setDecisionNote("Identity and device profile reviewed."); }}><Check data-icon="inline-start" />Approve</Button>
                    <Button size="sm" variant="destructive" onClick={() => { setDecision({ request, action: "reject" }); setDecisionNote(""); }}><X data-icon="inline-start" />Reject</Button>
                  </>}
                </div>
              </article>
            ))}
          </div>
        )}
      </Card>

      <Card>
        <SectionHeading title="Registered device inventory" description="Reviewable device facts only. Hardware identifiers and precise location are never collected." />
        <div className="grid gap-3 border-b p-5 md:grid-cols-[minmax(16rem,1fr)_12rem_auto]">
          <div className="relative"><Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" /><Input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search roll, student, or key fingerprint" className="pl-9" /></div>
          <Select value={status} onValueChange={(value) => value && setStatus(value)}><SelectTrigger className="h-10 w-full"><SelectValue /></SelectTrigger><SelectContent><SelectGroup><SelectItem value="all">All states</SelectItem><SelectItem value="ACTIVE">Active</SelectItem><SelectItem value="PENDING">Pending</SelectItem><SelectItem value="REVOKED">Revoked</SelectItem></SelectGroup></SelectContent></Select>
          <Button onClick={() => void load()}>Apply filters</Button>
        </div>
        {devices.length === 0 ? <p className="px-5 py-12 text-center text-sm text-muted-foreground">No devices match the current filters.</p> : (
          <div className="grid gap-4 p-5 md:grid-cols-2 2xl:grid-cols-3">
            {devices.map((device) => (
              <Link className="group rounded-lg border bg-card p-4 transition-[transform,box-shadow] hover:-translate-y-0.5 hover:shadow-[0_18px_40px_-34px_oklch(0.28_0.08_145)]" href={`/admin/devices/${device.id}`} key={device.id}>
                <div className="flex items-start justify-between gap-4"><DeviceVisual manufacturer={device.manufacturer} platform={device.platform} /><StatusBadge tone={device.status === "ACTIVE" ? "success" : device.status === "REVOKED" ? "error" : "warning"}>{device.status}</StatusBadge></div>
                <p className="mt-5 font-mono text-[11px] text-primary">{device.device_reference}</p>
                <h3 className="mt-1 truncate text-base font-semibold">{device.manufacturer ?? device.platform} {device.device_model ?? "Attendance device"}</h3>
                <p className="mt-1 truncate text-sm text-muted-foreground">{device.student_name} · {device.roll_number}</p>
                <dl className="mt-4 grid gap-2 border-t pt-3 text-xs"><DeviceFact label="Section" value={device.section_code} /><DeviceFact label="Integrity" value={device.integrity_status.replaceAll("_", " ")} /><DeviceFact label="Last seen" value={dateTime(device.last_seen_at)} /></dl>
                <div className="mt-4 flex items-center justify-between text-xs font-medium text-primary"><span>Open device record</span><ChevronRight className="size-4 transition-transform group-hover:translate-x-0.5" /></div>
              </Link>
            ))}
          </div>
        )}
      </Card>

      <Dialog open={Boolean(decision)} onOpenChange={(open) => { if (!open) setDecision(null); }}>
        <DialogContent>
          <DialogHeader><DialogTitle>{decision?.action === "approve" ? "Approve device replacement" : "Reject device replacement"}</DialogTitle><DialogDescription>{decision ? `${decision.request.student_name} · ${decision.request.roll_number}` : "Record an ICT decision."}</DialogDescription></DialogHeader>
          <Field><FieldLabel htmlFor="decision-note">{decision?.action === "approve" ? "Approval note" : "Rejection reason"}</FieldLabel><Textarea id="decision-note" value={decisionNote} onChange={(event) => setDecisionNote(event.target.value)} rows={4} /><FieldDescription>This note becomes part of the immutable device audit history.</FieldDescription></Field>
          <DialogFooter><Button variant="outline" onClick={() => setDecision(null)}>Cancel</Button><Button variant={decision?.action === "reject" ? "destructive" : "default"} disabled={loading || decisionNote.trim().length < 3} onClick={() => void submitDecision()}>{decision?.action === "approve" ? <Check data-icon="inline-start" /> : <X data-icon="inline-start" />}{decision?.action === "approve" ? "Approve replacement" : "Reject request"}</Button></DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={Boolean(activation)} onOpenChange={(open) => { if (!open) setActivation(null); }}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader><DialogTitle>Activate the approved device</DialogTitle><DialogDescription>This single-use QR expires at {dateTime(activation?.expires_at)} and only authorizes the reviewed replacement device.</DialogDescription></DialogHeader>
          {activationImage ? <div className="mx-auto w-full max-w-sm rounded-lg border bg-white p-4"><img className="block h-auto w-full" src={activationImage} alt="One-time device activation QR" /></div> : null}
          <DialogFooter><Button variant="outline" onClick={() => setActivation(null)}>Close</Button></DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}

function DeviceFact({ label, value }: { label: string; value: string }) {
  return <div className="grid grid-cols-[5rem_minmax(0,1fr)] gap-2"><dt className="text-muted-foreground">{label}</dt><dd className="truncate text-right font-medium">{value}</dd></div>;
}
