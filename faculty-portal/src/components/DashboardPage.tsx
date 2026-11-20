"use client";

import { useRouter } from "next/navigation";
import {
  AlertTriangle,
  ArrowRight,
  CalendarDays,
  CheckCircle2,
  ChevronRight,
  Clock3,
  CloudOff,
  DoorOpen,
  GraduationCap,
  Play,
  QrCode,
  Radio,
  RefreshCw,
  Users,
} from "lucide-react";
import type { FacultyClass } from "@/api";
import { dayPart, formatTime, isSameDay, minutes, presentCount, stateLabel } from "@/lib/format";
import { usePortalData } from "./FacultyPortalProvider";
import { Button } from "@/components/ui/button";
import { ErrorPanel, LoadingPanel, StatusBadge } from "./PortalUI";

function formatClock(value: string): string {
  if (!value.includes("T")) return formatTime(value);
  return new Intl.DateTimeFormat("en-IN", { hour: "2-digit", minute: "2-digit", hour12: false }).format(new Date(value));
}

export function DashboardPage() {
  const router = useRouter();
  const {
    classes,
    facultyCourses,
    facultyIdentity,
    register,
    roster,
    session,
    sessionHistory,
    online,
    start,
    loading,
    error,
    refresh,
  } = usePortalData();
  const activeSession = session && !session.closed_at ? session : null;
  const nowMinutes = new Date().getHours() * 60 + new Date().getMinutes();
  const next = classes.find((item) => minutes(item.end_time) >= nowMinutes) ?? null;
  const commandClass = activeSession ?? next;
  const completedToday = sessionHistory.filter((item) => isSameDay(new Date(item.scheduled_start), new Date()) && item.state === "CLOSED").length;
  const offlineReady = classes.filter((item) => item.offline_ready).length;
  const pendingRoster = activeSession ? Math.max(0, roster.length - presentCount(roster)) : 0;
  const pendingSync = activeSession ? pendingRoster : classes.filter((item) => !item.offline_ready).length;
  const belowThreshold = register ? register.students.filter((student) => student.present + student.absent > 0 && student.percentage < 75).length : 0;
  const recent = sessionHistory.slice(0, 4);

  async function openSession(item: FacultyClass) {
    if (await start(item.course_offering_id)) router.push("/attendance");
  }

  async function startNext() {
    if (next) await openSession(next);
  }

  const metrics = [
    { label: "Classes today", value: classes.length, detail: `${offlineReady} ready offline`, icon: CalendarDays },
    { label: "Pending reconciliation", value: pendingSync, detail: online ? "Service connected" : "Saved locally", icon: online ? RefreshCw : CloudOff },
    { label: "Completed today", value: completedToday, detail: "Closed sessions", icon: CheckCircle2 },
    { label: "Below 75%", value: belowThreshold, detail: "Require review", icon: AlertTriangle },
  ];

  if (loading && classes.length === 0 && facultyCourses.length === 0) return <LoadingPanel rows={6} label="Loading dashboard" className="dashboard-canvas rounded-xl bg-card" />;

  if (error && classes.length === 0 && facultyCourses.length === 0) return <ErrorPanel className="m-0" message={error} onRetry={() => void refresh()} />;
  if (!online && classes.length === 0 && facultyCourses.length === 0) return <ErrorPanel className="m-0" title="You are offline" message="No synchronized data is saved on this device yet." onRetry={() => void refresh()} />;

  return (
    <section className="dashboard-canvas overflow-hidden rounded-xl bg-card" aria-labelledby="dashboard-title">
      <header className="flex flex-col gap-5 px-5 pb-6 pt-6 sm:px-7 lg:flex-row lg:items-start lg:justify-between lg:px-9 lg:pb-7 lg:pt-8">
        <div className="min-w-0">
          <p className="text-xs font-medium text-primary">Faculty workspace</p>
          <h2 id="dashboard-title" className="mt-2 max-w-4xl text-balance text-fluid-3xl font-semibold leading-[1.08]">
            Good {dayPart()}, {facultyIdentity?.display_name ?? "Faculty"}
          </h2>
          <p className="mt-3 max-w-2xl text-pretty text-sm leading-6 text-muted-foreground sm:text-base">
            Run today&apos;s classes and review verified attendance from one workspace.
          </p>
        </div>
        <div className="flex shrink-0 items-center gap-2">
          <StatusBadge tone={online ? "success" : "warning"} icon={online ? Radio : CloudOff}>
            {online ? "Live sync ready" : "Offline ready"}
          </StatusBadge>
          <Button variant="ghost" size="sm" onClick={() => router.push("/records")}>
            Records<ArrowRight data-icon="inline-end" />
          </Button>
        </div>
      </header>

      <section className="mx-3 rounded-lg bg-[color-mix(in_oklab,var(--accent)_54%,white)] px-5 py-5 sm:mx-5 sm:px-6 lg:mx-7 lg:grid lg:grid-cols-[minmax(0,1fr)_auto] lg:items-center lg:gap-8 lg:px-7 lg:py-6" aria-label="Class command">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-xs font-semibold text-primary">{activeSession ? "Attendance live" : next ? "Next class" : "Teaching status"}</span>
            {activeSession ? <span className="size-1.5 rounded-full bg-primary motion-safe:animate-pulse" aria-hidden="true" /> : null}
          </div>
          <h3 className="mt-2 max-w-3xl text-balance text-2xl font-semibold leading-tight sm:text-3xl">
            {commandClass?.course_name ?? "Your teaching schedule is complete"}
          </h3>
          {commandClass ? (
            <div className="mt-5 flex flex-wrap gap-x-6 gap-y-3 text-sm text-muted-foreground">
              <span className="flex items-center gap-2"><Clock3 className="size-4 text-primary" />{formatClock(activeSession?.scheduled_start ?? next?.start_time ?? "")} - {formatClock(activeSession?.scheduled_end ?? next?.end_time ?? "")}</span>
              <span className="flex items-center gap-2"><DoorOpen className="size-4 text-primary" />Room {commandClass.room ?? "TBC"}</span>
              <span className="flex items-center gap-2"><Users className="size-4 text-primary" />{activeSession ? `${presentCount(roster)} of ${roster.length} verified` : `${commandClass.course_code} · ${commandClass.section_code}`}</span>
            </div>
          ) : (
            <p className="mt-3 text-sm leading-6 text-muted-foreground">Completed sessions remain available in Records for review and export.</p>
          )}
        </div>
        <div className="mt-6 flex flex-wrap gap-2 lg:mt-0 lg:w-52 lg:flex-col">
          {activeSession ? (
            <Button size="lg" onClick={() => router.push("/attendance")}><QrCode data-icon="inline-start" />Open attendance</Button>
          ) : next ? (
            <Button size="lg" onClick={() => void startNext()}><Play data-icon="inline-start" />Start attendance</Button>
          ) : null}
          <Button variant="outline" className="bg-white/70" onClick={() => router.push("/classes")}><CalendarDays data-icon="inline-start" />Teaching plan</Button>
        </div>
      </section>

      <section className="mx-5 grid grid-cols-2 gap-y-5 py-6 sm:mx-7 lg:grid-cols-4 lg:gap-y-0" aria-label="Today at a glance">
        {metrics.map(({ label, value, detail, icon: Icon }, index) => (
          <article className={`flex min-w-0 items-center gap-3 px-1 lg:px-5 ${index > 0 ? "lg:border-l lg:border-border/55" : ""}`} key={label}>
            <span className="flex size-9 shrink-0 items-center justify-center rounded-full bg-primary/10 text-primary"><Icon className="size-4" /></span>
            <div className="min-w-0">
              <div className="flex items-start gap-2">
                <strong className="text-2xl font-semibold tabular-nums">{value}</strong>
                <span className="pt-1 text-[11px] font-medium leading-4 text-foreground sm:text-xs">{label}</span>
              </div>
              <p className="mt-0.5 text-[11px] leading-4 text-muted-foreground sm:text-xs">{detail}</p>
            </div>
          </article>
        ))}
      </section>

      <div className="grid gap-0 border-t border-border/60 lg:grid-cols-[minmax(0,1.65fr)_minmax(18rem,0.75fr)]">
        <section className="min-w-0 px-5 py-6 sm:px-7 lg:px-9 lg:py-8" aria-labelledby="teaching-plan-title">
          <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <h3 id="teaching-plan-title" className="text-xl font-semibold">Today&apos;s teaching plan</h3>
              <p className="mt-1 text-sm text-muted-foreground">Start attendance directly from your synchronized schedule.</p>
            </div>
            <Button variant="ghost" size="sm" onClick={() => router.push("/classes")}>View full schedule<ChevronRight data-icon="inline-end" /></Button>
          </div>

          {classes.length ? (
            <div className="mt-6 space-y-1">
              {classes.map((item, index) => {
                const isActive = Boolean(activeSession?.course_offering_id === item.course_offering_id);
                const anotherActive = Boolean(activeSession && !isActive);
                return (
                  <article className={`group grid gap-4 rounded-lg px-3 py-4 transition-colors sm:grid-cols-[4.5rem_minmax(0,1fr)_auto] sm:items-center ${isActive ? "bg-primary/10" : "hover:bg-muted/55"}`} key={`${item.course_offering_id}:${index}`}>
                    <time className="text-sm font-semibold tabular-nums">
                      {formatTime(item.start_time)}
                      <span className="block text-xs font-normal text-muted-foreground">{formatTime(item.end_time)}</span>
                    </time>
                    <div className="min-w-0">
                      <div className="flex flex-wrap items-center gap-2">
                        <strong className="truncate text-sm font-semibold">{item.course_name}</strong>
                        {isActive ? <StatusBadge tone="success" icon={Radio}>Live</StatusBadge> : null}
                      </div>
                      <p className="mt-1 flex flex-wrap gap-x-3 gap-y-1 text-xs text-muted-foreground">
                        <span>{item.course_code} · {item.section_code}</span>
                        <span>Room {item.room}</span>
                        <span>{stateLabel(item, session)}</span>
                      </p>
                    </div>
                    <div className="flex items-center">
                      <Button size="sm" variant={isActive ? "default" : "outline"} disabled={anotherActive} onClick={() => isActive ? router.push("/attendance") : void openSession(item)}>
                        {isActive ? "Open attendance" : "Start attendance"}
                      </Button>
                    </div>
                  </article>
                );
              })}
            </div>
          ) : (
            <div className="grid min-h-56 place-items-center py-8 text-center">
              <div>
                <span className="mx-auto flex size-10 items-center justify-center rounded-full bg-muted text-muted-foreground"><CalendarDays className="size-5" /></span>
                <h4 className="mt-4 text-sm font-semibold">No more classes today</h4>
                <p className="mt-2 max-w-sm text-sm leading-6 text-muted-foreground">Your next synchronized teaching day will appear here automatically.</p>
              </div>
            </div>
          )}
        </section>

        <aside className="bg-muted/40 px-5 py-6 sm:px-7 lg:px-6 lg:py-8" aria-labelledby="recent-sessions-title">
          <div className="flex items-start justify-between gap-3">
            <div>
              <h3 id="recent-sessions-title" className="text-lg font-semibold">Recent attendance</h3>
              <p className="mt-1 text-sm text-muted-foreground">Latest session outcomes</p>
            </div>
            <Button variant="ghost" size="sm" onClick={() => router.push("/records")}>View all<ArrowRight data-icon="inline-end" /></Button>
          </div>
          <div className="mt-6">
            {recent.length ? recent.map((item, index) => {
              const percentage = item.expected ? Math.round((item.present / item.expected) * 100) : 0;
              return (
                <button className="group relative flex w-full items-start gap-3 pb-5 text-left last:pb-0" key={item.id} onClick={() => router.push("/records")}>
                  <span className="relative z-10 mt-1.5 size-2 shrink-0 rounded-full bg-primary ring-4 ring-muted" />
                  {index < recent.length - 1 ? <span className="absolute bottom-0 left-[3px] top-3 w-px bg-primary/20" aria-hidden="true" /> : null}
                  <span className="min-w-0 flex-1">
                    <span className="flex items-center justify-between gap-3">
                      <strong className="truncate text-sm">{item.course_code} · {item.section_code}</strong>
                      <ChevronRight className="size-4 shrink-0 text-muted-foreground transition-transform group-hover:translate-x-0.5" />
                    </span>
                    <span className="mt-1 block text-xs text-muted-foreground">{item.present} of {item.expected} present · {percentage}%</span>
                  </span>
                </button>
              );
            }) : <p className="py-12 text-center text-sm leading-6 text-muted-foreground">Closed attendance sessions will appear here.</p>}
          </div>
        </aside>
      </div>

      <footer className="grid gap-5 border-t border-border/60 bg-muted/20 px-5 py-5 sm:px-7 lg:grid-cols-[15rem_minmax(0,1fr)_auto] lg:items-center lg:px-9">
        <div>
          <h3 className="text-base font-semibold">Assigned courses</h3>
          <p className="mt-1 text-xs text-muted-foreground">Available to your account</p>
        </div>
        <div className="grid min-w-0 gap-3 sm:grid-cols-2">
          {facultyCourses.slice(0, 2).map((course) => (
            <button className="flex min-w-0 items-center gap-3 rounded-md px-2 py-2 text-left transition-colors hover:bg-card" key={course.course_offering_id} onClick={() => router.push("/classes")}>
              <span className="flex size-9 shrink-0 items-center justify-center rounded-full bg-primary/10 text-primary"><GraduationCap className="size-4" /></span>
              <span className="min-w-0">
                <strong className="block truncate text-sm font-medium">{course.course_name}</strong>
                <span className="block truncate text-xs text-muted-foreground">{course.section_code} · {course.student_count} students · {course.schedule_summary}</span>
              </span>
            </button>
          ))}
          {!facultyCourses.length ? <p className="text-sm text-muted-foreground">Assigned courses will appear after synchronization.</p> : null}
        </div>
        <Button variant="ghost" size="sm" onClick={() => router.push("/classes")}>View courses<ArrowRight data-icon="inline-end" /></Button>
      </footer>
    </section>
  );
}
