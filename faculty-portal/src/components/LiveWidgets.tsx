"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { QR_EPOCH_SECONDS } from "@/protocol";
import styles from "./ops.module.css";

/** Glowing progress ring. `value` and `max` are plain numbers; the arc is drawn with pathLength=100. */
export function ProgressRing({ value, max, size = 120, stroke = 10, tone = "ok", children, label }: {
  value: number;
  max: number;
  size?: number;
  stroke?: number;
  tone?: "ok" | "warn" | "bad";
  children?: React.ReactNode;
  label?: string;
}) {
  const pct = max > 0 ? Math.max(0, Math.min(100, (value / max) * 100)) : 0;
  const radius = 50 - stroke / 2;
  return (
    <div className={styles.ring} data-tone={tone} style={{ width: size, height: size }} role={label ? "img" : undefined} aria-label={label}>
      <svg viewBox="0 0 100 100" aria-hidden="true">
        <circle className={styles.ringTrack} cx="50" cy="50" r={radius} strokeWidth={stroke} fill="none" />
        <circle className={styles.ringArc} cx="50" cy="50" r={radius} strokeWidth={stroke} fill="none" pathLength={100} strokeDasharray="100" strokeDashoffset={100 - pct} strokeLinecap="round" transform="rotate(-90 50 50)" />
      </svg>
      <div className={styles.ringCenter}>{children}</div>
    </div>
  );
}

/** Countdown to the next QR epoch drawn as a draining ring. Ticks itself; the parent never re-renders. */
export function EpochRing({ startedAt, size = 84 }: { startedAt: string; size?: number }) {
  const [state, setState] = useState<{ seconds: string; elapsed: number; sync: number }>({ seconds: "--", elapsed: 0, sync: 0 });
  useEffect(() => {
    const origin = new Date(startedAt).getTime();
    const read = () => {
      const elapsed = Math.max(0, (Date.now() - origin) / 1000);
      const inEpoch = elapsed % QR_EPOCH_SECONDS;
      return { seconds: String(Math.max(1, Math.ceil(QR_EPOCH_SECONDS - inEpoch))), inEpoch };
    };
    const sync = () => {
      const { seconds, inEpoch } = read();
      setState((previous) => ({ seconds, elapsed: inEpoch, sync: previous.sync + 1 }));
    };
    sync();
    const timer = window.setInterval(() => {
      const { seconds } = read();
      setState((previous) => previous.seconds === seconds ? previous : { ...previous, seconds });
    }, 250);
    const onVisible = () => { if (document.visibilityState === "visible") sync(); };
    document.addEventListener("visibilitychange", onVisible);
    return () => { window.clearInterval(timer); document.removeEventListener("visibilitychange", onVisible); };
  }, [startedAt]);
  return (
    <div className={styles.epoch} style={{ width: size, height: size }} role="timer" aria-label={`Next code in ${state.seconds} seconds`}>
      <svg viewBox="0 0 100 100" aria-hidden="true">
        <circle className={styles.ringTrack} cx="50" cy="50" r="44" strokeWidth="7" fill="none" />
        <circle key={state.sync} className={styles.epochArc} cx="50" cy="50" r="44" strokeWidth="7" fill="none" pathLength={100} strokeDasharray="100" strokeLinecap="round" transform="rotate(-90 50 50)" style={{ animationDuration: `${QR_EPOCH_SECONDS}s`, animationDelay: `-${state.elapsed}s` }} />
      </svg>
      <span className={styles.epochNumber} aria-hidden="true">{state.seconds}</span>
    </div>
  );
}

/** Renders a growing window over a long list. Attach `sentinelRef` to an element after the last row. */
export function useChunked(total: number, step: number, resetKey: string) {
  const [state, setState] = useState({ key: resetKey, count: step });
  const count = Math.min(total, state.key === resetKey ? state.count : step);
  const observer = useRef<IntersectionObserver | null>(null);
  const sentinelRef = useCallback((node: HTMLElement | null) => {
    observer.current?.disconnect();
    observer.current = null;
    if (!node) return;
    observer.current = new IntersectionObserver((entries) => {
      if (entries.some((entry) => entry.isIntersecting)) {
        setState((previous) => ({ key: resetKey, count: (previous.key === resetKey ? previous.count : step) + step }));
      }
    }, { rootMargin: "800px" });
    observer.current.observe(node);
  }, [resetKey, step]);
  useEffect(() => () => observer.current?.disconnect(), []);
  const more = () => setState((previous) => ({ key: resetKey, count: (previous.key === resetKey ? previous.count : step) + step }));
  return { count, hasMore: count < total, sentinelRef, more };
}

export function initials(name: string): string {
  return name.trim().split(/\s+/).slice(0, 2).map((part) => part[0]?.toUpperCase() ?? "").join("") || "?";
}
