import type { LucideIcon } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
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
    <header className="grid gap-5 border-b-2 border-l-2 border-b-border border-l-primary px-5 py-4 lg:grid-cols-[minmax(0,1fr)_auto] lg:items-end">
      <div className="min-w-0">
        {eyebrow ? <p className="mb-2 text-xs font-semibold uppercase tracking-[0.14em] text-primary">{eyebrow}</p> : null}
        <h2 className="text-balance text-3xl font-semibold leading-tight tracking-tight md:text-4xl">{title}</h2>
        {description ? <p className="mt-2 max-w-3xl text-pretty text-sm leading-6 text-muted-foreground md:text-base">{description}</p> : null}
      </div>
      {actions ? <div className="flex flex-wrap items-center gap-2">{actions}</div> : null}
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
    <div className="flex flex-col gap-3 border-b-2 border-b-border px-5 pb-4 sm:flex-row sm:items-start sm:justify-between">
      <div>
        <h3 className="text-lg font-semibold tracking-tight">{title}</h3>
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
    <section className={cn("grid overflow-hidden rounded-lg border bg-card shadow-[0_12px_36px_-30px_oklch(0.28_0.08_145)] sm:grid-cols-2 xl:grid-cols-4", className)}>
      {metrics.map(({ label, value, icon: Icon, detail }, index) => (
        <article className={cn("min-w-0 bg-card px-5 py-4", index > 0 && "border-t sm:border-l sm:border-t-0", index === 2 && "sm:border-l-0 sm:border-t xl:border-l xl:border-t-0")} key={label}>
          <div className="flex items-center gap-2 text-xs font-medium text-muted-foreground">
            <span className="flex size-7 items-center justify-center rounded-md bg-primary/10 text-primary"><Icon className="size-4" aria-hidden="true" /></span>
            <span>{label}</span>
          </div>
          <strong className="mt-2 block text-2xl font-semibold tracking-tight">{value}</strong>
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
