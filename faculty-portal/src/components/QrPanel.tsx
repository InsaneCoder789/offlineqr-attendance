"use client";

import QRCode from "qrcode";
import { memo, useEffect, useRef, useState } from "react";
import { CheckCircle2, Clock3, DoorOpen, Maximize2, Minimize2, Radio, Square, Users, WifiOff } from "lucide-react";
import { createQrPayload, epochFor, QR_EPOCH_SECONDS, secondsUntilNextEpoch } from "@/protocol";
import { presentCount } from "@/lib/format";
import { usePortalData } from "./FacultyPortalProvider";
import { usePortalUiActions } from "./PortalUiState";
import { Button } from "@/components/ui/button";
import { StatusBadge } from "./PortalUI";
import type { FacultySession } from "../api";

/** Ticks once a second on its own so the surrounding panel never re-renders for it. */
function Countdown({ startedAt, prefix = "", suffix = "" }: { startedAt: string; prefix?: string; suffix?: string }) {
  const [seconds, setSeconds] = useState("--");
  useEffect(() => {
    const origin = new Date(startedAt);
    const tick = () => setSeconds(secondsUntilNextEpoch(new Date(), origin).toString().padStart(2, "0"));
    tick();
    const timer = window.setInterval(tick, 1000);
    return () => window.clearInterval(timer);
  }, [startedAt]);
  return <>{prefix}{seconds}{suffix}</>;
}

/** Draws the QR only when the epoch changes (every QR_EPOCH_SECONDS), not on every clock tick. */
function useQrCanvas(canvasRef: React.RefObject<HTMLCanvasElement | null>, authorization: FacultySession["authorization"] | undefined, startedAt: string | undefined, width: number) {
  // Session refetches hand back a new but identical authorization object; key on its signature.
  const authRef = useRef(authorization);
  authRef.current = authorization;
  const authKey = authorization?.server_signature;
  useEffect(() => {
    if (!authKey || !startedAt) return;
    const origin = new Date(startedAt);
    let cancelled = false;
    let timer: number | undefined;
    let drawnEpoch = -1;

    async function draw() {
      const now = new Date();
      const epoch = epochFor(now, origin);
      const authorization = authRef.current;
      if (epoch !== drawnEpoch && canvasRef.current && authorization) {
        drawnEpoch = epoch;
        const payload = await createQrPayload(authorization, startedAt as string, now);
        if (cancelled || !canvasRef.current) return;
        await QRCode.toCanvas(canvasRef.current, JSON.stringify(payload), {
          width,
          margin: 2,
          color: { dark: "#102119", light: "#ffffff" },
          errorCorrectionLevel: "M",
        });
      }
      if (cancelled) return;
      // Wake at the next epoch boundary (plus a small margin) instead of polling.
      const next = origin.getTime() + (epochFor(new Date(), origin) + 1) * QR_EPOCH_SECONDS * 1000;
      timer = window.setTimeout(() => void draw(), Math.max(50, next - Date.now() + 20));
    }
    void draw();
    return () => { cancelled = true; if (timer !== undefined) window.clearTimeout(timer); };
  }, [authKey, canvasRef, startedAt, width]);
}

export const QrPanel = memo(function QrPanel({ projector = false }: { projector?: boolean }) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const { session, roster, online, endSession } = usePortalData();
  const { setProjectorMode } = usePortalUiActions();
  useQrCanvas(canvasRef, session?.authorization, session?.started_at, projector ? 720 : 520);

  if (!session) return null;
  const present = presentCount(roster);
  const total = roster.length;
  const pending = Math.max(0, total - present);
  const liveSummary = <p role="status" aria-live="polite" aria-atomic="true" className="sr-only">{present} of {total} students marked present.</p>;

  if (projector) {
    return (
      <main className="projector-stage flex min-h-dvh flex-col gap-4 p-4 sm:p-6 lg:p-8">
        <header className="flex flex-wrap items-start justify-between gap-3 border-b pb-4">
          <div className="min-w-0">
            <p className="text-xs font-semibold uppercase tracking-[0.14em] text-primary sm:text-sm">Live attendance · {session.course_code} · {session.section_code}</p>
            <h1 className="mt-1 text-balance text-fluid-2xl font-semibold tracking-tight">{session.course_name}</h1>
            <p className="mt-1 flex items-center gap-2 text-sm text-muted-foreground sm:text-base"><DoorOpen className="size-4 sm:size-5" />{session.room ?? "Room TBC"}</p>
          </div>
          <Button variant="outline" size="lg" onClick={() => setProjectorMode(false)}><Minimize2 data-icon="inline-start" />Exit projector</Button>
        </header>
        <section className="grid min-h-0 flex-1 content-center items-center gap-6 lg:grid-cols-[minmax(0,1fr)_minmax(14rem,20rem)] lg:gap-10">
          <div className="projector-qr mx-auto flex w-full justify-center rounded-lg border bg-white p-3 sm:p-5">
            <canvas ref={canvasRef} role="img" className="qr-canvas" aria-label="Dynamic attendance QR code, refreshes every 5 seconds" />
          </div>
          <div className="flex flex-col gap-4 sm:gap-6">
            <div>
              <p className="text-sm font-medium text-muted-foreground">QR refresh</p>
              <strong className="mt-1 block text-5xl font-semibold tracking-tight text-primary sm:text-6xl lg:text-7xl"><Countdown startedAt={session.started_at} prefix="0:" /></strong>
              <p className="mt-2 max-w-xs text-pretty text-sm leading-6 text-muted-foreground sm:text-base">Students must scan inside the Institution attendance app. Each displayed code rotates after five seconds.</p>
            </div>
            <div className="grid grid-cols-2 gap-3 border-t pt-4">
              <div><span className="text-sm text-muted-foreground">Present</span><strong className="mt-1 block text-3xl sm:text-4xl">{present}</strong></div>
              <div><span className="text-sm text-muted-foreground">Expected</span><strong className="mt-1 block text-3xl sm:text-4xl">{total}</strong></div>
            </div>
            <div><StatusBadge tone={online ? "success" : "warning"} icon={online ? Radio : WifiOff}>{online ? "Roster updating live" : "Session running offline"}</StatusBadge></div>
            {liveSummary}
          </div>
        </section>
      </main>
    );
  }

  return (
    <section className="min-w-0 self-start bg-muted/30 p-4 sm:p-5 xl:sticky xl:top-22 xl:p-6">
      <header>
        <h2 className="text-fluid-lg font-semibold">{session.course_name}</h2>
        <p className="mt-1 text-sm text-muted-foreground">{session.course_code} · {session.section_code} · {session.room ?? "Room TBC"}</p>
        <div className="mt-2"><StatusBadge tone="success" icon={Radio}>Attendance active</StatusBadge></div>
      </header>
      <div className="mt-4 flex flex-col gap-4">
        <div className="live-qr mx-auto flex w-full justify-center rounded-lg bg-white p-3 shadow-sm">
          <canvas ref={canvasRef} role="img" className="qr-canvas" aria-label="Dynamic attendance QR code, refreshes every 5 seconds" />
        </div>
        <div className="grid grid-cols-3 overflow-hidden rounded-lg bg-card">
          <SessionFact icon={Clock3} label="Refresh" value={<Countdown startedAt={session.started_at} suffix="s" />} />
          <SessionFact icon={Users} label="Present" value={`${present}/${total}`} />
          <SessionFact icon={CheckCircle2} label="Pending" value={String(pending)} />
        </div>
        {liveSummary}
        <p className="text-pretty text-xs leading-5 text-muted-foreground">{online ? "The roster updates automatically when verified student proofs reach the attendance service." : "The signed QR continues from cached session credentials. Valid proofs reconcile when connectivity returns."}</p>
        <div className="grid gap-2 sm:grid-cols-2 xl:grid-cols-1 2xl:grid-cols-2">
          <Button size="lg" variant="outline" onClick={() => setProjectorMode(true)} aria-label="Open projector mode, full-screen QR"><Maximize2 data-icon="inline-start" />Projector mode</Button>
          <Button size="lg" variant="destructive" onClick={() => void endSession()}><Square data-icon="inline-start" />End attendance</Button>
        </div>
      </div>
    </section>
  );
});

function SessionFact({ icon: Icon, label, value }: { icon: typeof Clock3; label: string; value: React.ReactNode }) {
  return (
    <div className="min-w-0 border-l px-3 py-3 first:border-l-0">
      <span className="flex items-center gap-1 truncate text-[11px] text-muted-foreground"><Icon className="size-3.5" />{label}</span>
      <strong className="mt-1 block truncate text-sm">{value}</strong>
    </div>
  );
}
