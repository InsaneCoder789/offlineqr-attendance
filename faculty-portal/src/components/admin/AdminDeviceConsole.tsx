"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import QRCode from "qrcode";
import { AlertTriangle, Check, ChevronRight, History, RefreshCw, Search, ShieldCheck, Smartphone, SlidersHorizontal, X } from "lucide-react";
import { adminApi, type AdminDevice, type AdminStats, type DeviceActivationQr, type ReplacementRequest } from "@/admin-api";
import { DeviceVisual } from "./DeviceVisual";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Sheet, SheetContent, SheetDescription, SheetFooter, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Field, FieldDescription, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectGroup, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { EmptyPanel, MetricStrip, PageIntro, SectionHeading, StatusBadge } from "../PortalUI";

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
  const [filtersOpen, setFiltersOpen] = useState(false);
  const [loaded, setLoaded] = useState(false);

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

  return (
    <>
      <PageIntro
        eyebrow="ICT administration"
        title="Device governance"
        description="Review attendance-device bindings, approve controlled replacements, and inspect immutable device history."
        actions={<Button variant="outline" disabled={loading} onClick={() => void load()}><RefreshCw data-icon="inline-start" className={loading ? "animate-spin" : undefined} />Refresh data</Button>}
      />
      {error ? <Alert variant="destructive"><AlertTriangle /><AlertTitle>Governance service unavailable</AlertTitle><AlertDescription><span>{error}</span><Button className="mt-3 w-fit" size="sm" variant="outline" disabled={loading} onClick={() => void load()}><RefreshCw data-icon="inline-start" />Try again</Button></AlertDescription></Alert> : null}

      <Card>
        <SectionHeading title="Replacement approvals" description="A new device remains inactive until an ICT decision is recorded." action={<StatusBadge tone={replacements.length ? "warning" : "success"}>{loaded ? `${replacements.length} pending` : "Loading"}</StatusBadge>} />
        {!loaded && !error ? (
          <div className="divide-y" aria-busy="true" aria-label="Loading replacement requests">{[0, 1].map((key) => <div className="flex items-center gap-3 px-4 py-4 sm:px-5" key={key}><Skeleton className="size-11 rounded-lg" /><div className="flex-1 space-y-2"><Skeleton className="h-4 w-1/2" /><Skeleton className="h-3 w-3/4" /></div></div>)}</div>
        ) : replacements.length === 0 ? <EmptyPanel icon={ShieldCheck} title="Queue clear" description="No replacement requests require review." className="m-4 min-h-40 sm:m-5" /> : (
          <ul className="divide-y">
            {replacements.map((request) => (
              <li className="grid gap-4 px-4 py-4 sm:px-5 lg:grid-cols-[auto_minmax(0,1fr)_auto_auto] lg:items-center" key={request.id}>
                <div className="flex items-center justify-between gap-3 lg:contents">
                  <DeviceVisual manufacturer={request.new_manufacturer} platform={request.new_platform} />
                  <span className="lg:order-3"><StatusBadge tone={request.new_integrity_status.includes("FAIL") ? "error" : "neutral"}>{request.new_integrity_status.replaceAll("_", " ")}</StatusBadge></span>
                </div>
                <div className="min-w-0 lg:order-2">
                  <div className="flex flex-wrap items-center gap-x-2"><strong className="text-sm">{request.student_name}</strong><span className="font-mono text-xs text-muted-foreground">{request.roll_number}</span></div>
                  <p className="mt-1 break-words text-sm text-muted-foreground">{request.old_manufacturer ?? request.old_platform} {request.old_model ?? "device"} → {request.new_manufacturer ?? request.new_platform} {request.new_model ?? "device"}</p>
                  <p className="mt-1 break-words text-xs text-muted-foreground">{request.reason} · requested {dateTime(request.requested_at)}</p>
                </div>
                <div className="grid grid-cols-2 gap-2 sm:flex lg:order-4">
                  {request.status === "APPROVED" ? <Button className="col-span-2 min-h-11 sm:min-h-0" size="sm" onClick={() => void showActivation(request.id).catch((cause: unknown) => setError(cause instanceof Error ? cause.message : "Could not create activation QR."))}>Show activation QR</Button> : <>
                    <Button className="min-h-11 sm:min-h-0" size="sm" onClick={() => { setDecision({ request, action: "approve" }); setDecisionNote("Identity and device profile reviewed."); }}><Check data-icon="inline-start" />Approve</Button>
                    <Button className="min-h-11 sm:min-h-0" size="sm" variant="destructive" onClick={() => { setDecision({ request, action: "reject" }); setDecisionNote(""); }}><X data-icon="inline-start" />Reject</Button>
                  </>}
                </div>
              </li>
            ))}
          </ul>
        )}
      </Card>

      <MetricStrip className="xl:grid-cols-5" metrics={[
        { label: "Registered devices", value: stats?.total_devices ?? "-", icon: Smartphone },
        { label: "Active bindings", value: stats?.active_devices ?? "-", icon: ShieldCheck },
        { label: "Pending switches", value: stats?.pending_replacements ?? "-", icon: History },
        { label: "Manual review", value: stats?.review_required ?? "-", icon: AlertTriangle },
        { label: "Revoked", value: stats?.revoked_devices ?? "-", icon: X },
      ]} />

      <Card>
        <SectionHeading title="Registered device inventory" description="Reviewable device facts only. Hardware identifiers and precise location are never collected." />
        <form className="flex gap-2 border-b p-4 sm:p-5 md:grid md:grid-cols-[minmax(16rem,1fr)_12rem_auto]" onSubmit={(event) => { event.preventDefault(); void load(); }} role="search">
          <div className="relative min-w-0 flex-1"><Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" aria-hidden="true" /><Input aria-label="Search devices" value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search roll, student, or fingerprint" className="h-11 pl-9 md:h-10" /></div>
          <Button type="button" variant="outline" className="h-11 md:hidden" onClick={() => setFiltersOpen(true)} aria-label={status === "all" ? "Open filters" : "Open filters, one active"}><SlidersHorizontal data-icon="inline-start" />Filters{status !== "all" ? " (1)" : ""}</Button>
          <div className="hidden md:block"><StatusSelect status={status} setStatus={setStatus} /></div>
          <Button type="submit" className="hidden md:inline-flex" disabled={loading}>Apply filters</Button>
        </form>
        {!loaded && !error ? (
          <div className="grid gap-3 p-4 sm:p-5 md:grid-cols-2 2xl:grid-cols-3" aria-busy="true" aria-label="Loading devices">{[0, 1, 2].map((key) => <Skeleton className="h-44 rounded-lg" key={key} />)}</div>
        ) : devices.length === 0 ? <EmptyPanel icon={Smartphone} title="No devices found" description={query || status !== "all" ? "No devices match the current filters." : "No attendance devices are registered yet."} className="m-4 sm:m-5" /> : (
          <>
            <ul className="grid gap-3 p-4 sm:p-5 md:hidden">
              {devices.map((device) => (
                <li key={device.id}>
                  <Link className="block rounded-lg border bg-card p-4 active:bg-muted" href={`/admin/devices/${device.id}`}>
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
                      <TableCell><Link className="inline-flex size-9 items-center justify-center rounded-md text-primary hover:bg-muted" href={`/admin/devices/${device.id}`} aria-label={`Open record for ${device.student_name}`}><ChevronRight className="size-4" /></Link></TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          </>
        )}
      </Card>

      <Sheet open={filtersOpen} onOpenChange={setFiltersOpen}>
        <SheetContent side="bottom" className="max-h-[85dvh] pb-[env(safe-area-inset-bottom)]">
          <SheetHeader><SheetTitle>Filter devices</SheetTitle><SheetDescription>Narrow the inventory by binding state.</SheetDescription></SheetHeader>
          <div className="px-4"><Field><FieldLabel>Binding state</FieldLabel><StatusSelect status={status} setStatus={setStatus} /></Field></div>
          <SheetFooter><Button className="h-11" onClick={() => { setFiltersOpen(false); void load(); }}>Apply filters</Button><Button className="h-11" variant="outline" onClick={() => { setStatus("all"); }}>Reset</Button></SheetFooter>
        </SheetContent>
      </Sheet>

      <Dialog open={Boolean(decision)} onOpenChange={(open) => { if (!open) setDecision(null); }}>
        <DialogContent>
          <DialogHeader><DialogTitle>{decision?.action === "approve" ? "Approve device replacement" : "Reject device replacement"}</DialogTitle><DialogDescription>{decision ? `${decision.request.student_name} · ${decision.request.roll_number}` : "Record an ICT decision."}</DialogDescription></DialogHeader>
          {decision ? <div className="rounded-lg border bg-muted/40 p-3 text-sm"><p className="break-words">{decision.request.old_manufacturer ?? decision.request.old_platform} {decision.request.old_model ?? "device"} → {decision.request.new_manufacturer ?? decision.request.new_platform} {decision.request.new_model ?? "device"}</p><p className="mt-1 text-xs text-muted-foreground">{decision.action === "approve" ? "Approving issues a single-use activation QR for the new device." : "Rejecting keeps the current binding unchanged and closes this request."}</p></div> : null}
          <Field><FieldLabel htmlFor="decision-note">{decision?.action === "approve" ? "Approval note" : "Rejection reason"}</FieldLabel><Textarea id="decision-note" value={decisionNote} onChange={(event) => setDecisionNote(event.target.value)} rows={4} /><FieldDescription>This note becomes part of the immutable device audit history.</FieldDescription></Field>
          {error ? <p className="text-sm text-destructive" role="alert">{error}</p> : null}
          <DialogFooter><Button variant="outline" disabled={loading} onClick={() => setDecision(null)}>Cancel</Button><Button variant={decision?.action === "reject" ? "destructive" : "default"} disabled={loading || decisionNote.trim().length < 3} onClick={() => void submitDecision()}>{decision?.action === "approve" ? <Check data-icon="inline-start" /> : <X data-icon="inline-start" />}{loading ? "Recording decision" : decision?.action === "approve" ? "Approve replacement" : "Reject request"}</Button></DialogFooter>
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

function deviceTone(status: string) {
  return status === "ACTIVE" ? "success" : status === "REVOKED" ? "error" : "warning";
}

function StatusSelect({ status, setStatus }: { status: string; setStatus: (value: string) => void }) {
  return (
    <Select value={status} onValueChange={(value) => value && setStatus(value)}>
      <SelectTrigger className="h-11 w-full md:h-10" aria-label="Binding state"><SelectValue /></SelectTrigger>
      <SelectContent><SelectGroup><SelectItem value="all">All states</SelectItem><SelectItem value="ACTIVE">Active</SelectItem><SelectItem value="PENDING">Pending</SelectItem><SelectItem value="REVOKED">Revoked</SelectItem></SelectGroup></SelectContent>
    </Select>
  );
}
