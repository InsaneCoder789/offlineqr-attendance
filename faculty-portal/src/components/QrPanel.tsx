"use client";

import QRCode from "qrcode";
import { memo, useEffect, useRef, useState } from "react";
import { Maximize2, Minimize2, Square } from "lucide-react";
import { createQrPayload, epochFor, QR_EPOCH_SECONDS } from "@/protocol";
import { usePortalData } from "./FacultyPortalProvider";
import { usePortalUiActions } from "./PortalUiState";
import { EpochRing } from "./LiveWidgets";
import { Button } from "./ui/button";
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "./ui/dialog";
import live from "./attendance.module.css";
import styles from "./ops.module.css";
import type { FacultySession } from "../api";

/** Draws the QR only when the epoch changes (every QR_EPOCH_SECONDS), not on every clock tick. */
function useQrCanvas(canvasRef: React.RefObject<HTMLCanvasElement | null>, authorization: FacultySession["authorization"] | undefined, startedAt: string | undefined, width: number) {
  const [result, setResult] = useState<{ key: string; state: "ready" | "failed" }>();
  // Session refetches hand back a new but identical authorization object; key on its signature.
  const authRef = useRef(authorization);
  authRef.current = authorization;
  const authKey = authorization?.session_private_key ? authorization.server_signature : undefined;
  const drawKey = `${authKey ?? ""}:${startedAt ?? ""}`;
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
        try {
          const payload = await createQrPayload(authorization, startedAt as string, now);
          if (cancelled || !canvasRef.current) return;
          await QRCode.toCanvas(canvasRef.current, JSON.stringify(payload), {
            width,
            margin: 2,
            color: { dark: "#0b1510", light: "#ffffff" },
            errorCorrectionLevel: "M",
          });
          if (!cancelled) {
            drawnEpoch = epoch;
            setResult((previous) => previous?.key === drawKey && previous.state === "ready" ? previous : { key: drawKey, state: "ready" });
          }
        } catch {
          if (!cancelled) setResult((previous) => previous?.key === drawKey && previous.state === "failed" ? previous : { key: drawKey, state: "failed" });
        }
      }
      if (cancelled) return;
      // Wake at the next epoch boundary (plus a small margin) instead of polling.
      const next = origin.getTime() + (epochFor(new Date(), origin) + 1) * QR_EPOCH_SECONDS * 1000;
      timer = window.setTimeout(() => void draw(), Math.max(50, next - Date.now() + 20));
    }
    void draw();
    return () => { cancelled = true; if (timer !== undefined) window.clearTimeout(timer); };
  }, [authKey, canvasRef, drawKey, startedAt, width]);
  if (!authKey || !startedAt) return "unavailable";
  return result?.key === drawKey ? result.state : "loading";
}

export const QrPanel = memo(function QrPanel({ projector = false }: { projector?: boolean }) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const { session, online, endSession, loading } = usePortalData();
  const { setProjectorMode } = usePortalUiActions();
  const [showClose, setShowClose] = useState(false);
  const closing = useRef(false);
  const qrState = useQrCanvas(canvasRef, session?.authorization, session?.started_at, projector ? 1024 : 600);
  const qrMessage = qrState === "failed" ? "Could not generate QR. Retrying automatically." : qrState === "unavailable" ? "QR signing is unavailable for this session." : "Preparing QR…";
  const qrNotice = qrState !== "ready" && <p role={qrState === "loading" ? "status" : "alert"}>{qrMessage}</p>;

  // Projector: Esc exits; try real fullscreen, and leave projector mode if the browser leaves fullscreen.
  useEffect(() => {
    if (!projector) return;
    let enteredFullscreen = false;
    const onKey = (event: KeyboardEvent) => { if (event.key === "Escape") setProjectorMode(false); };
    const onFullscreen = () => { if (enteredFullscreen && !document.fullscreenElement) setProjectorMode(false); };
    window.addEventListener("keydown", onKey);
    document.addEventListener("fullscreenchange", onFullscreen);
    try {
      void document.documentElement.requestFullscreen?.().then(() => { enteredFullscreen = true; }).catch(() => undefined);
    } catch { /* fullscreen is optional */ }
    return () => {
      window.removeEventListener("keydown", onKey);
      document.removeEventListener("fullscreenchange", onFullscreen);
      enteredFullscreen = false;
      if (document.fullscreenElement) void document.exitFullscreen().catch(() => undefined);
    };
  }, [projector, setProjectorMode]);

  if (!session) return null;
  if (projector) {
    return (
      <main className={live.projector} aria-label="Projector mode">
        <header className={live.projectorHead}>
          <div>
            <p className={live.kicker}>{session.course_code} · {session.section_code}</p>
            <h1>{session.course_name}</h1>
          </div>
          <Button variant="outline" size="sm" onClick={() => setProjectorMode(false)}><Minimize2 aria-hidden="true" />Exit<span className="hidden sm:inline"> (Esc)</span></Button>
        </header>
        <div className={live.projectorCode}>
          {qrNotice}
          <canvas ref={canvasRef} role="img" className={styles.qrCanvas} style={{ visibility: qrState === "ready" ? "visible" : "hidden" }} aria-label="Dynamic attendance QR code, refreshes every 5 seconds" />
        </div>
        <div className={live.projectorCaption}>
          {qrState === "ready" && <EpochRing startedAt={session.started_at} size={52} />}
          <p>Scan with the attendance app.</p>
        </div>
      </main>
    );
  }

  return (
    <section className={live.scan} aria-labelledby="scan-heading">
      <h3 id="scan-heading">Classroom QR</h3>
      <div className={live.canvasFrame}>
        {qrNotice}
        <canvas ref={canvasRef} role="img" className={styles.qrCanvas} style={{ visibility: qrState === "ready" ? "visible" : "hidden" }} aria-label="Dynamic attendance QR code, refreshes every 5 seconds" />
      </div>
      <div className={styles.qrTimerRow}>
        {qrState === "ready" && <EpochRing startedAt={session.started_at} size={56} />}
        <p className={styles.qrNote}>{online ? "Students scan with the attendance app. A new code appears every five seconds." : "Offline. Students can save scans on their phones and submit them when they reconnect."}</p>
      </div>
      <div className={live.controls}>
        <Button variant="outline" disabled={qrState !== "ready"} onClick={() => setProjectorMode(true)}><Maximize2 aria-hidden="true" />Projector mode</Button>
        <Dialog open={showClose} onOpenChange={(open) => { if (!closing.current) setShowClose(open); }}>
          <DialogTrigger disabled={loading} render={<Button variant="destructive" />}><Square aria-hidden="true" />End attendance</DialogTrigger>
          <DialogContent showCloseButton={false}>
            <DialogHeader>
              <DialogTitle>End attendance?</DialogTitle>
              <DialogDescription>The classroom QR will stop rotating. Students can still submit eligible scans captured before the session ended.</DialogDescription>
            </DialogHeader>
            <DialogFooter>
              <DialogClose disabled={loading} render={<Button variant="outline" />}>Keep session open</DialogClose>
              <Button variant="destructive" disabled={loading} onClick={async () => {
                if (closing.current) return;
                closing.current = true;
                try {
                  await endSession();
                  setShowClose(false);
                } finally {
                  closing.current = false;
                }
              }}>{loading ? "Ending…" : "End session"}</Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>
    </section>
  );
});
