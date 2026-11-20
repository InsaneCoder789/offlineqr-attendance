"use client";

import { useSyncExternalStore } from "react";
import { AlertTriangle, RefreshCw } from "lucide-react";
import type { LucideIcon } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

type StatusTone = "success" | "warning" | "neutral" | "error";

export function StatusBadge({
  children,
  icon: Icon,
  tone = "neutral",
}: {
  children: React.ReactNode;
  icon?: LucideIcon;
  tone?: StatusTone;
}) {
  const variant = tone === "success" ? "success" : tone === "warning" ? "warning" : tone === "error" ? "destructive" : "secondary";
  return (
    <Badge variant={variant}>
      {Icon ? <Icon data-icon="inline-start" /> : null}
      {children}
    </Badge>
  );
}

export function PageIntro({
  eyebrow,
  title,
  description,
  actions,
}: {
  eyebrow?: string;
  title: string;
  description?: string;
  actions?: React.ReactNode;
}) {
  return (
    <header className="grid gap-4 px-1 py-2 sm:gap-5 sm:py-3 lg:grid-cols-[minmax(0,1fr)_auto] lg:items-end">
      <div className="min-w-0">
        {eyebrow ? <p className="mb-2 text-xs font-medium text-primary">{eyebrow}</p> : null}
        <h2 className="text-balance text-fluid-3xl font-semibold leading-tight">{title}</h2>
        {description ? <p className="mt-2 max-w-3xl text-pretty text-sm leading-6 text-muted-foreground md:text-base">{description}</p> : null}
      </div>
      {actions ? <div className="flex flex-wrap items-center gap-2 [&>*]:max-sm:flex-1">{actions}</div> : null}
    </header>
  );
}

export function SectionHeading({
  title,
  description,
  action,
}: {
  title: string;
  description?: string;
  action?: React.ReactNode;
}) {
  return (
    <div className="flex flex-col gap-3 border-b border-b-border px-5 py-4 sm:flex-row sm:items-start sm:justify-between">
      <div>
        <h3 className="text-lg font-semibold">{title}</h3>
        {description ? <p className="mt-1 text-sm leading-5 text-muted-foreground">{description}</p> : null}
      </div>
      {action}
    </div>
  );
}

export function MetricStrip({
  metrics,
  className,
}: {
  metrics: Array<{ label: string; value: string | number; icon: LucideIcon; detail?: string }>;
  className?: string;
}) {
  return (
    <section className={cn("dashboard-canvas grid overflow-hidden rounded-xl bg-card p-2 sm:grid-cols-2 xl:grid-cols-4", className)}>
      {metrics.map(({ label, value, icon: Icon, detail }, index) => (
        <article className={cn("min-w-0 rounded-lg px-4 py-3", index > 0 && "xl:border-l xl:border-border/55")} key={label}>
          <div className="flex items-center gap-2 text-xs font-medium text-muted-foreground">
            <span className="flex size-7 items-center justify-center rounded-md bg-primary/10 text-primary"><Icon className="size-4" aria-hidden="true" /></span>
            <span>{label}</span>
          </div>
          <strong className="mt-2 block text-2xl font-semibold tabular-nums">{value}</strong>
          {detail ? <span className="mt-1 block truncate text-xs text-muted-foreground">{detail}</span> : null}
        </article>
      ))}
    </section>
  );
}

export function EmptyPanel({
  icon: Icon,
  title,
  description,
  action,
  className,
}: {
  icon: LucideIcon;
  title: string;
  description: string;
  action?: React.ReactNode;
  className?: string;
}) {
  return (
    <Empty className={cn("min-h-56 border", className)}>
      <EmptyHeader>
        <EmptyMedia variant="icon"><Icon /></EmptyMedia>
        <EmptyTitle>{title}</EmptyTitle>
        <EmptyDescription>{description}</EmptyDescription>
      </EmptyHeader>
      {action}
    </Empty>
  );
}

/** Subscribes to a min-width media query. Server and first paint assume the narrow layout. */
export function useMinWidth(px: number): boolean {
  return useSyncExternalStore(
    (notify) => {
      const query = window.matchMedia(`(min-width: ${px}px)`);
      query.addEventListener("change", notify);
      return () => query.removeEventListener("change", notify);
    },
    () => window.matchMedia(`(min-width: ${px}px)`).matches,
    () => false,
  );
}

/** Shared loading placeholder: stacked skeleton rows with an accessible busy status. */
export function LoadingPanel({ rows = 4, label = "Loading", className }: { rows?: number; label?: string; className?: string }) {
  return (
    <div role="status" aria-busy="true" className={cn("grid gap-3 p-5", className)}>
      <span className="sr-only">{label}</span>
      {Array.from({ length: rows }, (_, index) => <Skeleton key={index} className="h-14 w-full rounded-lg" />)}
    </div>
  );
}

/** Shared inline error with optional retry. */
export function ErrorPanel({ title = "Could not load this view", message, onRetry, className }: { title?: string; message: string; onRetry?: () => void; className?: string }) {
  return (
    <div role="alert" className={cn("m-5 flex flex-col items-start gap-3 rounded-lg border border-destructive/30 bg-destructive/5 p-4 sm:flex-row sm:items-center sm:justify-between", className)}>
      <div className="flex min-w-0 items-start gap-3">
        <AlertTriangle className="mt-0.5 size-5 shrink-0 text-destructive" aria-hidden="true" />
        <div className="min-w-0"><strong className="block text-sm font-semibold">{title}</strong><p className="mt-1 break-words text-sm text-muted-foreground">{message}</p></div>
      </div>
      {onRetry ? <Button variant="outline" onClick={onRetry}><RefreshCw data-icon="inline-start" />Retry</Button> : null}
    </div>
  );
}
