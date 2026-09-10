"use client";

import QRCode from "qrcode";
import { useEffect, useRef, useState } from "react";
import { CheckCircle2, Clock3, DoorOpen, Maximize2, Minimize2, Radio, Square, Users, WifiOff } from "lucide-react";
import { createQrPayload, secondsUntilNextEpoch } from "@/protocol";
import { presentCount } from "@/lib/format";
import { useFacultyPortal } from "./FacultyPortalProvider";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { StatusBadge } from "./PortalUI";

export function QrPanel({ projector = false }: { projector?: boolean }) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const [countdown, setCountdown] = useState("--");
  const { session, roster, online, setProjectorMode, endSession } = useFacultyPortal();

  useEffect(() => {
    let cancelled = false;
    async function renderQr() {
      if (!session || !canvasRef.current) return;
      const payload = await createQrPayload(session.authorization, session.started_at);
      if (cancelled) return;
      await QRCode.toCanvas(canvasRef.current, JSON.stringify(payload), {
        width: projector ? 720 : 520,
        margin: 2,
        color: { dark: "#102119", light: "#ffffff" },
        errorCorrectionLevel: "M",
      });
      setCountdown(secondsUntilNextEpoch(new Date(), new Date(session.started_at)).toString().padStart(2, "0"));
    }
    void renderQr();
    const timer = window.setInterval(renderQr, 1000);
    return () => { cancelled = true; window.clearInterval(timer); };
  }, [projector, session]);

  if (!session) return null;
  const present = presentCount(roster);
  const total = roster.length;
  const pending = Math.max(0, total - present);

  if (projector) {
    return (
      <main className="projector-stage flex flex-col p-6 md:p-10">
        <header className="flex flex-wrap items-start justify-between gap-5 border-b pb-5">
          <div>
            <p className="text-sm font-semibold uppercase tracking-[0.14em] text-primary">Live attendance · {session.course_code} · {session.section_code}</p>
            <h1 className="mt-2 text-balance text-4xl font-semibold tracking-tight md:text-5xl">{session.course_name}</h1>
            <p className="mt-2 flex items-center gap-2 text-lg text-muted-foreground"><DoorOpen className="size-5" />{session.room ?? "Room TBC"}</p>
          </div>
          <Button variant="outline" size="lg" onClick={() => setProjectorMode(false)}><Minimize2 data-icon="inline-start" />Exit projector</Button>
        </header>
        <section className="grid flex-1 items-center gap-10 py-8 lg:grid-cols-[minmax(0,1fr)_22rem]">
          <div className="mx-auto w-full max-w-[min(65vh,44rem)] rounded-lg border bg-white p-5 shadow-[0_28px_70px_-52px_oklch(0.28_0.08_145)]">
            <canvas ref={canvasRef} className="qr-canvas mx-auto" aria-label="Dynamic attendance QR code, refreshes every 5 seconds" />
          </div>
          <div className="flex flex-col gap-8">
            <div>
              <p className="text-sm font-medium text-muted-foreground">QR refresh</p>
              <strong className="mt-1 block text-7xl font-semibold tracking-tight text-primary">0:{countdown}</strong>
              <p className="mt-3 max-w-xs text-pretty text-base leading-6 text-muted-foreground">Students must scan inside the KIIT attendance app. Each displayed code rotates after five seconds.</p>
            </div>
            <div className="grid grid-cols-2 gap-3 border-t pt-6">
              <div><span className="text-sm text-muted-foreground">Present</span><strong className="mt-1 block text-4xl">{present}</strong></div>
              <div><span className="text-sm text-muted-foreground">Expected</span><strong className="mt-1 block text-4xl">{total}</strong></div>
            </div>
            <StatusBadge tone={online ? "success" : "warning"} icon={online ? Radio : WifiOff}>{online ? "Roster updating live" : "Session running offline"}</StatusBadge>
          </div>
        </section>
      </main>
    );
  }

  return (
    <Card className="self-start xl:sticky xl:top-22">
      <CardHeader>
        <CardTitle>{session.course_name}</CardTitle>
        <CardDescription>{session.course_code} · {session.section_code} · {session.room ?? "Room TBC"}</CardDescription>
        <div className="mt-2"><StatusBadge tone="success" icon={Radio}>Attendance active</StatusBadge></div>
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        <div className="rounded-lg border bg-white p-3">
          <canvas ref={canvasRef} className="qr-canvas mx-auto" aria-label="Dynamic attendance QR code, refreshes every 5 seconds" />
        </div>
        <div className="grid grid-cols-3 overflow-hidden rounded-lg border bg-muted/35">
          <SessionFact icon={Clock3} label="Refresh" value={`${countdown}s`} />
          <SessionFact icon={Users} label="Present" value={`${present}/${total}`} />
          <SessionFact icon={CheckCircle2} label="Pending" value={String(pending)} />
        </div>
        <p className="text-pretty text-xs leading-5 text-muted-foreground">{online ? "The roster updates automatically when verified student proofs reach the attendance service." : "The signed QR continues from cached session credentials. Valid proofs reconcile when connectivity returns."}</p>
        <div className="grid gap-2 sm:grid-cols-2">
          <Button variant="outline" onClick={() => setProjectorMode(true)}><Maximize2 data-icon="inline-start" />Projector mode</Button>
          <Button variant="destructive" onClick={() => void endSession()}><Square data-icon="inline-start" />End attendance</Button>
        </div>
      </CardContent>
    </Card>
  );
}

function SessionFact({ icon: Icon, label, value }: { icon: typeof Clock3; label: string; value: string }) {
  return (
    <div className="min-w-0 border-l px-3 py-3 first:border-l-0">
      <span className="flex items-center gap-1 truncate text-[11px] text-muted-foreground"><Icon className="size-3.5" />{label}</span>
      <strong className="mt-1 block truncate text-sm">{value}</strong>
    </div>
  );
}
