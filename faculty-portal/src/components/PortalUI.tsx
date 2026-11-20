"use client";

import { useSyncExternalStore } from "react";
import { AlertTriangle, RefreshCw, WifiOff } from "lucide-react";
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
    <header className="silk-heading enter grid gap-4 sm:gap-5 sm:py-3 lg:grid-cols-[minmax(0,1fr)_auto] lg:items-end">
      <div className="min-w-0">
        {eyebrow ? <p className="eyebrow mb-2 !text-primary">{eyebrow}</p> : null}
        <h2 className="text-balance text-fluid-3xl font-bold leading-[1.05] tracking-tight">{title}</h2>
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
    <div className="flex flex-col gap-3 border-b border-b-border px-5 py-4 sm:flex-row sm:items-center sm:justify-between">
      <div>
        <h3 className="text-lg font-bold tracking-tight">{title}</h3>
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
    <section className={cn("grid gap-3 sm:grid-cols-2 xl:grid-cols-4", className)}>
      {metrics.map(({ label, value, icon: Icon, detail }, index) => (
        <article className={cn("glass-card enter min-w-0 p-5", index === 1 && "enter-2", index === 2 && "enter-3", index === 3 && "enter-4")} key={label}>
          <div className="flex items-center gap-2.5 text-xs font-semibold text-muted-foreground">
            <span className="flex size-8 items-center justify-center rounded-xl bg-primary/12 text-primary"><Icon className="size-4" aria-hidden="true" /></span>
            <span className="min-w-0 truncate">{label}</span>
          </div>
          <strong className="stat-figure mt-4 block">{value}</strong>
          {detail ? <span className="mt-2 block truncate text-xs text-muted-foreground">{detail}</span> : null}
        </article>
      ))}
    </section>
  );
}

/** Glowing circular progress. `value` is 0-100. Pure CSS conic-gradient, no chart library. */
export function ProgressRing({
  value,
  size = "4.5rem",
  tone = "success",
  label,
  className,
  children,
}: {
  value: number;
  size?: string;
  tone?: "success" | "warning" | "error";
  label?: string;
  className?: string;
  children?: React.ReactNode;
}) {
  const clamped = Math.max(0, Math.min(100, Number.isFinite(value) ? value : 0));
  const color = tone === "error" ? "var(--danger)" : tone === "warning" ? "var(--amber)" : "var(--neon)";
  return (
    <span
      role={label ? "img" : undefined}
      aria-label={label}
      className={cn("neon-ring", className)}
      style={{ "--p": clamped, "--ring-size": size, "--ring-color": color } as React.CSSProperties}
    >
      <span className="text-[0.8125rem] font-bold tabular-nums text-foreground">{children ?? `${Math.round(clamped)}%`}</span>
    </span>
  );
}

/** Tiny inline-SVG sparkline. Decorative unless `label` is set. */
export function Sparkline({
  points,
  className,
  tone = "success",
  label,
}: {
  points: number[];
  className?: string;
  tone?: "success" | "warning" | "error";
  label?: string;
}) {
  const data = points.length > 1 ? points : [0, 0];
  const max = Math.max(...data, 1);
  const min = Math.min(...data, 0);
  const span = max - min || 1;
  const w = 100;
  const h = 28;
  const coords = data.map((value, index) => [(index / (data.length - 1)) * w, h - 3 - ((value - min) / span) * (h - 6)] as const);
  const line = coords.map(([x, y], index) => `${index ? "L" : "M"}${x.toFixed(1)} ${y.toFixed(1)}`).join(" ");
  const area = `${line} L${w} ${h} L0 ${h} Z`;
  const color = tone === "error" ? "var(--danger)" : tone === "warning" ? "var(--amber)" : "var(--neon)";
  const id = `spark-${tone}`;
  return (
    <svg viewBox={`0 0 ${w} ${h}`} preserveAspectRatio="none" className={cn("h-7 w-full overflow-visible", className)} role={label ? "img" : undefined} aria-label={label} aria-hidden={label ? undefined : true}>
      <defs>
        <linearGradient id={id} x1="0" x2="0" y1="0" y2="1">
          <stop offset="0" stopColor={color} stopOpacity="0.35" />
          <stop offset="1" stopColor={color} stopOpacity="0" />
        </linearGradient>
      </defs>
      <path d={area} fill={`url(#${id})`} />
      <path d={line} fill="none" stroke={color} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" vectorEffect="non-scaling-stroke" style={{ filter: `drop-shadow(0 0 4px ${color})` }} />
    </svg>
  );
}

/** Big-numeral stat tile with icon, optional sparkline or ring. */
export function StatTile({
  label,
  value,
  detail,
  icon: Icon,
  tone = "success",
  spark,
  ring,
  className,
}: {
  label: string;
  value: string | number;
  detail?: string;
  icon: LucideIcon;
  tone?: "success" | "warning" | "error";
  spark?: number[];
  ring?: number;
  className?: string;
}) {
  const iconTone = tone === "error" ? "bg-danger-soft text-danger" : tone === "warning" ? "bg-amber-soft text-amber" : "bg-primary/12 text-primary";
  return (
    <article className={cn("glass-card enter flex min-w-0 flex-col gap-4 p-5", className)}>
      <div className="flex items-center justify-between gap-3">
        <div className="flex min-w-0 items-center gap-2.5 text-xs font-semibold text-muted-foreground">
          <span className={cn("flex size-9 shrink-0 items-center justify-center rounded-xl", iconTone)}><Icon className="size-4" aria-hidden="true" /></span>
          <span className="min-w-0 leading-tight">{label}</span>
        </div>
        {typeof ring === "number" ? <ProgressRing value={ring} size="2.75rem" tone={tone} /> : null}
      </div>
      <strong className="stat-figure">{value}</strong>
      <div className="min-w-0">
        {spark ? <Sparkline points={spark} tone={tone} className="mb-2" /> : null}
        {detail ? <p className="truncate text-xs text-muted-foreground">{detail}</p> : null}
      </div>
    </article>
  );
}

/** Block wrapper with a designed header; children render the block body. */
export function Panel({
  title,
  description,
  action,
  children,
  className,
  id,
}: {
  title: string;
  description?: string;
  action?: React.ReactNode;
  children: React.ReactNode;
  className?: string;
  id?: string;
}) {
  return (
    <section className={cn("glass-card enter min-w-0 overflow-hidden", className)} aria-labelledby={id}>
      <div className="flex items-start justify-between gap-3 px-5 pt-5 sm:px-6">
        <div className="min-w-0">
          <h3 id={id} className="text-lg font-bold tracking-tight">{title}</h3>
          {description ? <p className="mt-1 text-sm text-muted-foreground">{description}</p> : null}
        </div>
        {action}
      </div>
      <div className="min-w-0">{children}</div>
    </section>
  );
}

/** Slim offline/stale line shared by blocks. */
export function OfflineNote({ className, children }: { className?: string; children?: React.ReactNode }) {
  return (
    <p role="status" className={cn("flex items-center gap-2 rounded-xl border border-warning/30 bg-amber-soft px-3 py-2 text-xs font-medium text-foreground", className)}>
      <WifiOff className="size-3.5 shrink-0 text-warning" aria-hidden="true" />
      {children ?? "Offline. Showing data saved on this device."}
    </p>
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
    <Empty className={cn("min-h-56 border border-dashed border-border", className)}>
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
      {Array.from({ length: rows }, (_, index) => <Skeleton key={index} className="h-16 w-full rounded-2xl" />)}
    </div>
  );
}

/** Shared inline error with optional retry. */
export function ErrorPanel({ title = "Could not load this view", message, onRetry, className }: { title?: string; message: string; onRetry?: () => void; className?: string }) {
  return (
    <div role="alert" className={cn("m-5 flex flex-col items-start gap-3 rounded-2xl border border-destructive/35 bg-danger-soft p-4 sm:flex-row sm:items-center sm:justify-between", className)}>
      <div className="flex min-w-0 items-start gap-3">
        <AlertTriangle className="mt-0.5 size-5 shrink-0 text-destructive" aria-hidden="true" />
        <div className="min-w-0"><strong className="block text-sm font-semibold">{title}</strong><p className="mt-1 break-words text-sm text-muted-foreground">{message}</p></div>
      </div>
      {onRetry ? <Button variant="outline" onClick={onRetry} className="max-sm:w-full"><RefreshCw data-icon="inline-start" />Retry</Button> : null}
    </div>
  );
}

const courseHues = [150, 200, 265, 320, 25, 80, 175, 235];

/** Stable accent hue (oklch) for a course so every view colours it the same way. */
export function courseHue(key: string): number {
  let hash = 0;
  for (let index = 0; index < key.length; index += 1) hash = (hash * 31 + key.charCodeAt(index)) >>> 0;
  return courseHues[hash % courseHues.length];
}

export function courseAccentStyle(key: string): React.CSSProperties {
  return { "--h": courseHue(key) } as React.CSSProperties;
}
