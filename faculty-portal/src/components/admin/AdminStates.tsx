"use client";

import { useEffect, useState } from "react";
import { AlertTriangle, Lock, RefreshCw, WifiOff } from "lucide-react";
import { Button } from "@/components/ui/button";
import styles from "../dark-command.module.css";
import { cn } from "@/lib/utils";

export function dateTime(value?: string | null) {
  return value ? new Intl.DateTimeFormat("en-IN", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value)) : "Not recorded";
}

export function useOnline() {
  const [online, setOnline] = useState(true);
  useEffect(() => {
    const sync = () => setOnline(navigator.onLine);
    sync();
    window.addEventListener("online", sync);
    window.addEventListener("offline", sync);
    return () => { window.removeEventListener("online", sync); window.removeEventListener("offline", sync); };
  }, []);
  return online;
}

export function isForbidden(message: string | null) {
  return Boolean(message && /403|forbidden|not authori[sz]ed|administrator|permission/i.test(message));
}

/** Error / offline / forbidden state card with optional retry. */
export function StateCard({ kind, message, onRetry, busy }: { kind: "error" | "offline" | "forbidden"; message?: string | null; onRetry?: () => void; busy?: boolean }) {
  const Icon = kind === "forbidden" ? Lock : kind === "offline" ? WifiOff : AlertTriangle;
  const title = kind === "forbidden" ? "Administrator access required" : kind === "offline" ? "You are offline" : "Governance service unavailable";
  const text = kind === "forbidden" ? "Device governance is available to authorized institution administrators." : kind === "offline" ? "Device governance needs a live connection. Reconnect and try again." : message ?? "Something went wrong while loading this view.";
  return (
    <div role="alert" className={cn(kind === "error" ? styles.glassDanger : styles.glass, "flex flex-col items-start gap-4 rounded-3xl p-5 sm:flex-row sm:items-center sm:justify-between sm:p-6")}>
      <div className="flex min-w-0 items-start gap-3">
        <span className={cn("flex size-11 shrink-0 items-center justify-center rounded-xl", kind === "offline" || kind === "forbidden" ? "bg-warning/15 text-warning" : "bg-destructive/15 text-destructive")}><Icon className="size-5" aria-hidden="true" /></span>
        <div className="min-w-0"><strong className="block text-base font-semibold">{title}</strong><p className="mt-1 break-words text-sm text-muted-foreground">{text}</p></div>
      </div>
      {onRetry && kind !== "forbidden" ? <Button variant="outline" disabled={busy} onClick={onRetry}><RefreshCw data-icon="inline-start" className={busy ? "animate-spin" : undefined} />Try again</Button> : null}
    </div>
  );
}
