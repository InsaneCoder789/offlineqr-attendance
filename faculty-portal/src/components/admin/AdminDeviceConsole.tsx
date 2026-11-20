"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import QRCode from "qrcode";
import { ArrowRight, Check, ChevronRight, Flag, RefreshCw, Search, ShieldCheck, Smartphone, SlidersHorizontal, X } from "lucide-react";
import { adminApi, type AdminDevice, type AdminStats, type DeviceActivationQr, type ReplacementRequest } from "@/admin-api";
import { DeviceVisual } from "./DeviceVisual";
import { StateCard, dateTime, isForbidden, useOnline } from "./AdminStates";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Sheet, SheetContent, SheetDescription, SheetFooter, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Field, FieldDescription, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { PageIntro, StatusBadge } from "../PortalUI";
import styles from "../dark-command.module.css";
import { cn } from "@/lib/utils";

type Decision = { request: ReplacementRequest; action: "approve" | "reject" } | null;

const statusFilters = [
  { value: "all", label: "All states" },
  { value: "ACTIVE", label: "Active" },
  { value: "PENDING", label: "Pending" },
  { value: "REVOKED", label: "Revoked" },
];

function deviceName(manufacturer: string | null | undefined, platform: string, model: string | null | undefined) {
  return `${manufacturer ?? platform} ${model ?? "device"}`;
}

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
  const [filtersOpen, setFiltersOpen] = useState(false);
  const [draftStatus, setDraftStatus] = useState("all");
  const [loaded, setLoaded] = useState(false);
  const online = useOnline();

  async function load(nextStatus = status) {
    setLoading(true);
    setError(null);
    try {
      const [nextStats, nextDevices, nextReplacements] = await Promise.all([
        adminApi.stats(), adminApi.devices(query, nextStatus === "all" ? "" : nextStatus), adminApi.replacements(),
      ]);
      setStats(nextStats);
      setDevices(nextDevices);
      setReplacements(nextReplacements);
      setLoaded(true);
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

  function chooseStatus(value: string) { setStatus(value); void load(value); }

  const forbidden = isForbidden(error);
  const blocking = !loaded && Boolean(error);
  const flagged = stats?.review_required;
  const tiles = [
    { label: "Pending replacements", value: stats?.pending_replacements, glow: styles.glowWarn, hot: (stats?.pending_replacements ?? 0) > 0 },
    { label: "Active bindings", value: stats?.active_devices, glow: styles.glowText, hot: false },
    { label: "Revoked", value: stats?.revoked_devices, glow: styles.glowRed, hot: false },
    { label: "Flagged for review", value: flagged, glow: styles.glowWarn, hot: (flagged ?? 0) > 0 },
  ];

  return (
    <>
      <PageIntro
        eyebrow="ICT administration"
        title="Device governance"
        description="Review attendance-device bindings, approve controlled replacements, and inspect immutable device history."
        actions={<Button variant="outline" disabled={loading || !online} onClick={() => void load()}><RefreshCw data-icon="inline-start" className={loading ? "animate-spin" : undefined} />Refresh data</Button>}
      />
      {!online ? <StateCard kind="offline" onRetry={() => void load()} busy={loading} /> : null}
      {error && online ? <StateCard kind={forbidden ? "forbidden" : "error"} message={error} onRetry={() => void load()} busy={loading} /> : null}

      {!forbidden && !blocking ? (
        <>
          <section aria-label="Governance summary" className="teaching-metrics grid grid-cols-2 xl:grid-cols-4">
            {tiles.map((tile) => (
              <div key={tile.label} className={cn("min-w-0 p-4 sm:p-5", tile.hot && "text-warning")}>
                <p className="text-xs font-medium text-muted-foreground">{tile.label}</p>
                {tile.value === undefined ? <Skeleton className="mt-2 h-8 w-12 rounded-md" /> : <p className="mt-2 text-2xl font-semibold tabular-nums">{tile.value}</p>}
              </div>
            ))}
          </section>

          <section aria-labelledby="queue-heading" className="flex flex-col gap-3">
            <div className="flex flex-wrap items-end justify-between gap-2">
              <div><h2 id="queue-heading" className="text-lg font-semibold tracking-tight">Replacement approvals</h2><p className="text-sm text-muted-foreground">A new device remains inactive until an ICT decision is recorded.</p></div>
              <StatusBadge tone={replacements.length ? "warning" : "success"}>{loaded ? `${replacements.length} pending` : "Loading"}</StatusBadge>
            </div>
            {!loaded ? (
              <div className="grid gap-3 lg:grid-cols-2" aria-busy="true" aria-label="Loading replacement requests">{[0, 1].map((key) => <Skeleton className="h-56 rounded-3xl" key={key} />)}</div>
            ) : replacements.length === 0 ? (
              <div className={cn(styles.glass, "flex flex-col items-center gap-3 rounded-3xl px-6 py-12 text-center")}>
                <span className={cn(styles.celebrate, "flex size-16 items-center justify-center rounded-full bg-primary/15 text-primary")}><ShieldCheck className="size-8" aria-hidden="true" /></span>
                <h3 className="text-xl font-semibold">Queue clear</h3>
                <p className="max-w-sm text-sm text-muted-foreground">No replacement requests require review.</p>
              </div>
            ) : (
              <ul className="grid gap-3 lg:grid-cols-2">
                {replacements.map((request) => (
                  <li key={request.id} className={cn(styles.glass, "flex min-w-0 flex-col gap-4 rounded-3xl p-4 sm:p-5")}>
                    <div className="flex flex-wrap items-start justify-between gap-2">
                      <div className="min-w-0"><strong className="block break-words text-base">{request.student_name}</strong><span className="font-mono text-xs text-muted-foreground">{request.roll_number}</span></div>
                      <StatusBadge tone={request.new_integrity_status.includes("FAIL") ? "error" : "neutral"}>{request.new_integrity_status.replaceAll("_", " ")}</StatusBadge>
                    </div>
                    <div className="grid grid-cols-[minmax(0,1fr)_auto_minmax(0,1fr)] items-center gap-2 sm:gap-3">
                      <div className="min-w-0 rounded-2xl border bg-background/40 p-3"><p className="mb-2 text-[11px] font-semibold uppercase tracking-wider text-muted-foreground">Current</p><DeviceVisual manufacturer={request.old_manufacturer} platform={request.old_platform} className="size-9" /><p className="mt-2 break-words text-sm font-medium">{deviceName(request.old_manufacturer, request.old_platform, request.old_model)}</p></div>
                      <ArrowRight className="size-5 text-primary" aria-label="replaced by" />
                      <div className="min-w-0 rounded-2xl border border-primary/40 bg-primary/8 p-3"><p className="mb-2 text-[11px] font-semibold uppercase tracking-wider text-primary">Requested</p><DeviceVisual manufacturer={request.new_manufacturer} platform={request.new_platform} className="size-9" /><p className="mt-2 break-words text-sm font-medium">{deviceName(request.new_manufacturer, request.new_platform, request.new_model)}</p></div>
                    </div>
                    {request.new_risk_flags?.length ? <div className="flex flex-wrap gap-1.5">{request.new_risk_flags.map((flag) => <Badge key={flag} variant="warning" className="h-auto min-w-0 max-w-full whitespace-normal [overflow-wrap:anywhere]"><Flag className="shrink-0" data-icon="inline-start" aria-hidden="true" /><span className="min-w-0">{flag.replaceAll("_", " ")}</span></Badge>)}</div> : null}
                    <p className="break-words text-xs text-muted-foreground">{request.reason} · requested {dateTime(request.requested_at)}</p>
                    <div className="mt-auto grid grid-cols-2 gap-2">
                      {request.status === "APPROVED" ? <Button className="col-span-2 min-h-11" onClick={() => void showActivation(request.id).catch((cause: unknown) => setError(cause instanceof Error ? cause.message : "Could not create activation QR."))}>Show activation QR</Button> : <>
                        <Button className="min-h-11" onClick={() => { setDecision({ request, action: "approve" }); setDecisionNote("Identity and device profile reviewed."); }}><Check data-icon="inline-start" />Approve</Button>
                        <Button className="min-h-11" variant="destructive" onClick={() => { setDecision({ request, action: "reject" }); setDecisionNote(""); }}><X data-icon="inline-start" />Reject</Button>
                      </>}
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </section>

          <section aria-labelledby="inventory-heading" className="overflow-hidden rounded-lg border bg-card">
            <div className="p-4 sm:p-5">
              <h2 id="inventory-heading" className="text-lg font-semibold tracking-tight">Registered device inventory</h2>
              <p className="text-sm text-muted-foreground">Reviewable device facts only. Hardware identifiers and precise location are never collected.</p>
            </div>
            <form className="flex flex-col gap-3 border-y p-4 sm:p-5 xl:flex-row xl:items-center" onSubmit={(event) => { event.preventDefault(); void load(); }} role="search">
              <div className="flex min-w-0 flex-1 gap-2">
                <div className="relative min-w-0 flex-1"><Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" aria-hidden="true" /><Input aria-label="Search devices" value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search roll, student, or fingerprint" className="h-11 rounded-xl pl-9" /></div>
                <Button type="button" variant="outline" className="h-11 xl:hidden" onClick={() => { setDraftStatus(status); setFiltersOpen(true); }} aria-label={status === "all" ? "Open filters" : "Open filters, one active"}><SlidersHorizontal data-icon="inline-start" />Filters{status !== "all" ? " (1)" : ""}</Button>
              </div>
              <div className="hidden gap-2 xl:flex" role="group" aria-label="Binding state">
                {statusFilters.map((chip) => <button key={chip.value} type="button" aria-pressed={status === chip.value} onClick={() => chooseStatus(chip.value)} className={cn("min-h-11 rounded-full border px-4 text-sm font-medium transition-colors focus-visible:outline-2 focus-visible:outline-primary", status === chip.value ? "border-primary bg-primary text-primary-foreground" : "bg-background/40 text-muted-foreground hover:text-foreground")}>{chip.label}</button>)}
              </div>
              <Button type="submit" disabled={loading || !online}>Apply filters</Button>
            </form>
            {!loaded ? (
              <div className="grid gap-3 p-4 sm:p-5 md:grid-cols-2 2xl:grid-cols-3" aria-busy="true" aria-label="Loading devices">{[0, 1, 2].map((key) => <Skeleton className="h-44 rounded-2xl" key={key} />)}</div>
            ) : devices.length === 0 ? (
              <div className="flex flex-col items-center gap-2 px-6 py-12 text-center"><span className="flex size-12 items-center justify-center rounded-2xl bg-muted text-muted-foreground"><Smartphone className="size-6" aria-hidden="true" /></span><h3 className="font-semibold">No devices found</h3><p className="text-sm text-muted-foreground">{query || status !== "all" ? "No devices match the current filters." : "No attendance devices are registered yet."}</p></div>
            ) : (
              <>
                <ul className="grid gap-3 p-4 sm:p-5 md:hidden">
                  {devices.map((device) => (
                    <li key={device.id}>
                      <Link className="block rounded-2xl border bg-background/40 p-4 active:bg-muted focus-visible:outline-2 focus-visible:outline-primary" href={`/admin/devices/${device.id}`}>
                        <div className="flex items-start justify-between gap-3"><DeviceVisual manufacturer={device.manufacturer} platform={device.platform} /><StatusBadge tone={deviceTone(device.status)}>{device.status}</StatusBadge></div>
                        <p className="mt-4 break-all font-mono text-[11px] text-primary">{device.device_reference}</p>
                        <h3 className="mt-1 break-words text-base font-semibold">{device.manufacturer ?? device.platform} {device.device_model ?? "Attendance device"}</h3>
                        <p className="mt-1 break-words text-sm text-muted-foreground">{device.student_name} · {device.roll_number}</p>
                        <dl className="mt-4 grid gap-2 border-t pt-3 text-xs"><DeviceFact label="Section" value={device.section_code} /><DeviceFact label="Integrity" value={device.integrity_status.replaceAll("_", " ")} /><DeviceFact label="Last seen" value={dateTime(device.last_seen_at)} /></dl>
                        <div className="mt-3 flex items-center justify-between text-xs font-medium text-primary"><span>Open device record</span><ChevronRight className="size-4" aria-hidden="true" /></div>
                      </Link>
                    </li>
                  ))}
                </ul>
                <div className="hidden md:block">
                  <Table>
                    <TableHeader><TableRow><TableHead>Device</TableHead><TableHead>Student</TableHead><TableHead>Section</TableHead><TableHead>Integrity</TableHead><TableHead>Last seen</TableHead><TableHead>Status</TableHead><TableHead className="w-10"><span className="sr-only">Open</span></TableHead></TableRow></TableHeader>
                    <TableBody>
                      {devices.map((device) => (
                        <TableRow key={device.id}>
                          <TableCell><div className="flex items-center gap-3"><DeviceVisual manufacturer={device.manufacturer} platform={device.platform} className="size-9" /><div className="min-w-0"><p className="font-medium">{device.manufacturer ?? device.platform} {device.device_model ?? "Attendance device"}</p><p className="font-mono text-[11px] text-primary">{device.device_reference}</p></div></div></TableCell>
                          <TableCell><p className="font-medium">{device.student_name}</p><p className="font-mono text-xs text-muted-foreground">{device.roll_number}</p></TableCell>
                          <TableCell>{device.section_code}</TableCell>
                          <TableCell>{device.integrity_status.replaceAll("_", " ")}</TableCell>
                          <TableCell className="whitespace-nowrap">{dateTime(device.last_seen_at)}</TableCell>
                          <TableCell><StatusBadge tone={deviceTone(device.status)}>{device.status}</StatusBadge></TableCell>
                          <TableCell><Link className="inline-flex size-11 items-center justify-center rounded-lg text-primary hover:bg-muted focus-visible:outline-2 focus-visible:outline-primary" href={`/admin/devices/${device.id}`} aria-label={`Open record for ${device.student_name}`}><ChevronRight className="size-4" /></Link></TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </div>
              </>
            )}
          </section>
        </>
      ) : null}

      <Sheet open={filtersOpen} onOpenChange={setFiltersOpen}>
        <SheetContent side="bottom" className="max-h-[85dvh] pb-[env(safe-area-inset-bottom)]">
          <SheetHeader><SheetTitle>Filter devices</SheetTitle><SheetDescription>Narrow the inventory by binding state.</SheetDescription></SheetHeader>
          <div className="px-4"><Field><FieldLabel>Binding state</FieldLabel>
            <div className="flex flex-wrap gap-2" role="group" aria-label="Binding state">{statusFilters.map((chip) => <button key={chip.value} type="button" aria-pressed={draftStatus === chip.value} onClick={() => setDraftStatus(chip.value)} className={cn("min-h-11 rounded-full border px-4 text-sm font-medium", draftStatus === chip.value ? "border-primary bg-primary text-primary-foreground" : "text-muted-foreground")}>{chip.label}</button>)}</div></Field></div>
          <SheetFooter><Button className="h-11" disabled={loading || !online} onClick={() => { setStatus(draftStatus); setFiltersOpen(false); void load(draftStatus); }}>Apply filters</Button><Button className="h-11" variant="outline" onClick={() => setDraftStatus("all")}>Reset</Button></SheetFooter>
        </SheetContent>
      </Sheet>

      <Dialog open={Boolean(decision)} onOpenChange={(open) => { if (!open) setDecision(null); }}>
        <DialogContent>
          <DialogHeader><DialogTitle>{decision?.action === "approve" ? "Approve device replacement" : "Reject device replacement"}</DialogTitle><DialogDescription>{decision ? `${decision.request.student_name} · ${decision.request.roll_number}` : "Record an ICT decision."}</DialogDescription></DialogHeader>
          {decision ? <div className="rounded-xl border bg-muted/40 p-3 text-sm"><p className="break-words">{decision.request.old_manufacturer ?? decision.request.old_platform} {decision.request.old_model ?? "device"} → {decision.request.new_manufacturer ?? decision.request.new_platform} {decision.request.new_model ?? "device"}</p><p className="mt-1 text-xs text-muted-foreground">{decision.action === "approve" ? "Approving issues a single-use activation QR for the new device." : "Rejecting keeps the current binding unchanged and closes this request."}</p></div> : null}
          <Field><FieldLabel htmlFor="decision-note">{decision?.action === "approve" ? "Approval note" : "Rejection reason"}</FieldLabel><Textarea id="decision-note" value={decisionNote} onChange={(event) => setDecisionNote(event.target.value)} rows={4} /><FieldDescription>This note becomes part of the immutable device audit history.</FieldDescription></Field>
          {error ? <p className="text-sm text-destructive" role="alert">{error}</p> : null}
          <DialogFooter><Button variant="outline" disabled={loading} onClick={() => setDecision(null)}>Cancel</Button><Button variant={decision?.action === "reject" ? "destructive" : "default"} disabled={loading || decisionNote.trim().length < 3} onClick={() => void submitDecision()}>{decision?.action === "approve" ? <Check data-icon="inline-start" /> : <X data-icon="inline-start" />}{loading ? "Recording decision" : decision?.action === "approve" ? "Approve replacement" : "Reject request"}</Button></DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={Boolean(activation)} onOpenChange={(open) => { if (!open) setActivation(null); }}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader><DialogTitle>Activate the approved device</DialogTitle><DialogDescription>This single-use QR expires at {dateTime(activation?.expires_at)} and only authorizes the reviewed replacement device.</DialogDescription></DialogHeader>
          {activationImage ? <div className="mx-auto w-full max-w-sm rounded-2xl border bg-white p-4"><img className="block h-auto w-full" src={activationImage} alt="One-time device activation QR" /></div> : null}
          <DialogFooter><Button variant="outline" onClick={() => setActivation(null)}>Close</Button></DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}

function DeviceFact({ label, value }: { label: string; value: string }) {
  return <div className="grid grid-cols-[5rem_minmax(0,1fr)] gap-2"><dt className="text-muted-foreground">{label}</dt><dd className="truncate text-right font-medium">{value}</dd></div>;
}

function deviceTone(status: string) {
  return status === "ACTIVE" ? "success" : status === "REVOKED" ? "error" : "warning";
}
