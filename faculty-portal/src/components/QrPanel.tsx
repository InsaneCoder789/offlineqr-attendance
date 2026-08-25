"use client";

import QRCode from "qrcode";
import { useEffect, useRef, useState } from "react";
import { createQrPayload, secondsUntilNextEpoch } from "../protocol";
import { presentCount } from "../lib/format";
import { useFacultyPortal } from "./FacultyPortalProvider";
import { Icon } from "./Icons";

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
        width: projector ? 460 : 360,
        margin: 2,
        errorCorrectionLevel: "M",
      });
      setCountdown(secondsUntilNextEpoch(new Date(), new Date(session.started_at)).toString().padStart(2, "0"));
    }

    void renderQr();
    const timer = window.setInterval(renderQr, 1000);
    return () => {
      cancelled = true;
      window.clearInterval(timer);
    };
  }, [projector, session]);

  if (!session) return null;

  const present = presentCount(roster);
  const total = roster.length;
  const pending = Math.max(0, total - present);

  return (
    <section className={projector ? "projector" : "qr-panel"}>
      <div className="qr-header">
        <div className="qr-info">
          <h2>{session.course_name}</h2>
          <p>{session.course_code} | {session.section_code} | {session.room ?? "Room TBC"}</p>
        </div>
        <span className="status with-icon success">
          <Icon name="check" />
          Attendance Active
        </span>
      </div>
      <div className="qr-session-facts">
        <span><Icon name="classes" /><strong>{session.course_code}</strong></span>
        <span><Icon name="room" /><strong>{session.room ?? "Room TBC"}</strong></span>
        <span><Icon name="records" /><strong>{present}/{total || 0} present</strong></span>
      </div>
      <div className="qr-box">
        <canvas
          ref={canvasRef}
          width={projector ? 460 : 360}
          height={projector ? 460 : 360}
          aria-label="Dynamic attendance QR code, refreshes every 5 seconds"
        />
      </div>
      <div className="qr-meta">
        <span className="inline-status">
          <Icon name="clock" />
          Refreshes in <strong className="countdown">{countdown}</strong>s
        </span>
        <span><strong>{present}</strong> present · <strong>{pending}</strong> pending</span>
      </div>
      <p className="sync-hint">
        {online
          ? "Roster refreshes automatically as student proofs reach the backend."
          : "Offline mode: QR keeps rotating from cached session credentials. Proofs reconcile when internet returns."}
      </p>
      <div className="qr-actions">
        <button className="secondary" onClick={() => setProjectorMode(!projector)}>
          <Icon name="monitor" />
          {projector ? "Exit Projector" : "Projector Mode"}
        </button>
        <button className="danger" onClick={() => void endSession()}>
          <Icon name="stop" />
          End Attendance
        </button>
      </div>
    </section>
  );
}
