"use client";

import { useRouter } from "next/navigation";
import {
  AlertTriangle,
  ArrowRight,
  BookOpen,
  CalendarDays,
  CheckCircle2,
  Clock3,
  CloudOff,
  Play,
  QrCode,
  Radio,
  Users,
} from "lucide-react";
import { dayPart, formatTime, isSameDay, minutes, presentCount } from "@/lib/format";
import { ClassList } from "./ClassList";
import { CourseGrid } from "./CourseGrid";
import { useFacultyPortal } from "./FacultyPortalProvider";
import { Button } from "@/components/ui/button";
import { Card, CardAction, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { MetricStrip, PageIntro, SectionHeading, StatusBadge } from "./PortalUI";

export function DashboardPage() {
  const router = useRouter();
  const { classes, facultyIdentity, register, roster, session, sessionHistory, online, start } = useFacultyPortal();
  const activeSession = session && !session.closed_at ? session : null;
  const nowMinutes = new Date().getHours() * 60 + new Date().getMinutes();
  const next = classes.find((item) => minutes(item.end_time) >= nowMinutes) ?? null;
  const completedToday = sessionHistory.filter((item) => isSameDay(new Date(item.scheduled_start), new Date()) && item.state === "CLOSED").length;
  const offlineReady = classes.filter((item) => item.offline_ready).length;
  const pendingRoster = activeSession ? Math.max(0, roster.length - presentCount(roster)) : 0;
  const pendingSync = activeSession ? pendingRoster : classes.filter((item) => !item.offline_ready).length;
  const belowThreshold = register ? register.students.filter((student) => student.present + student.absent > 0 && student.percentage < 75).length : 0;
  const recent = sessionHistory.slice(0, 4);

  async function startNext() {
    if (next && await start(next.course_offering_id)) router.push("/attendance");
  }

  return (
    <>
      <PageIntro
        eyebrow="Faculty workspace"
        title={`Good ${dayPart()}, ${facultyIdentity?.display_name ?? "Faculty"}`}
        description="Your teaching schedule, live classroom attendance, and reconciliation workload in one operational view."
        actions={(
          <>
            <Button variant="outline" onClick={() => router.push("/records")}><BookOpen data-icon="inline-start" />Review records</Button>
            {activeSession ? (
              <Button onClick={() => router.push("/attendance")}><Radio data-icon="inline-start" />Open live session</Button>
            ) : next ? (
              <Button onClick={() => void startNext()}><Play data-icon="inline-start" />Start next class</Button>
            ) : null}
          </>
        )}
      />

      <MetricStrip metrics={[
        { label: "Classes today", value: classes.length, icon: CalendarDays, detail: `${offlineReady} prepared for offline use` },
        { label: "Pending reconciliation", value: pendingSync, icon: online ? Clock3 : CloudOff, detail: online ? "Connected to attendance service" : "Saved locally until reconnect" },
        { label: "Completed today", value: completedToday, icon: CheckCircle2, detail: "Closed teaching sessions" },
        { label: "Below 75%", value: belowThreshold, icon: AlertTriangle, detail: "Students requiring review" },
      ]} />

      <section className="grid gap-4 xl:grid-cols-[minmax(0,1.55fr)_minmax(20rem,0.7fr)]">
        <Card className="min-h-64">
          <CardHeader>
            <CardTitle>{activeSession ? "Attendance is live" : next ? "Next scheduled class" : "Teaching schedule complete"}</CardTitle>
            <CardDescription>{activeSession ? "The student roster updates as verified proofs arrive." : next ? "Start the session when the classroom is ready." : "No further classes are scheduled for today."}</CardDescription>
            <CardAction><StatusBadge tone={activeSession ? "success" : "neutral"} icon={activeSession ? Radio : Clock3}>{activeSession ? "Live" : next ? formatTime(next.start_time) : "Clear"}</StatusBadge></CardAction>
          </CardHeader>
          <CardContent className="flex flex-1 flex-col justify-between gap-8">
            <div>
              <p className="text-xs font-semibold uppercase tracking-[0.12em] text-primary">{activeSession?.course_code ?? next?.course_code ?? "Today"} · {activeSession?.section_code ?? next?.section_code ?? "Schedule"}</p>
              <h3 className="mt-2 max-w-3xl text-balance text-2xl font-semibold tracking-tight md:text-3xl">{activeSession?.course_name ?? next?.course_name ?? "No more classes"}</h3>
              <p className="mt-3 text-sm leading-6 text-muted-foreground">{activeSession
                ? `${activeSession.room ?? "Room TBC"} · ${presentCount(roster)} of ${roster.length} recorded · QR rotates every 5 seconds`
                : next ? `Room ${next.room} · ${formatTime(next.start_time)} to ${formatTime(next.end_time)} · ${next.offline_ready ? "Offline credentials ready" : "Online activation required"}`
                : "Your completed sessions remain available in Records for review and export."}</p>
            </div>
            <div className="flex flex-wrap items-center gap-2">
              {activeSession ? <Button onClick={() => router.push("/attendance")}><QrCode data-icon="inline-start" />Open live attendance</Button> : null}
              {!activeSession && next ? <Button onClick={() => void startNext()}><Play data-icon="inline-start" />Start attendance</Button> : null}
              <Button variant="ghost" onClick={() => router.push("/classes")}>View teaching plan<ArrowRight data-icon="inline-end" /></Button>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Recent sessions</CardTitle>
            <CardDescription>Latest attendance outcomes</CardDescription>
          </CardHeader>
          <CardContent className="flex flex-col gap-1">
            {recent.length ? recent.map((item) => (
              <button className="flex w-full items-center justify-between gap-4 rounded-lg px-2 py-3 text-left transition-colors hover:bg-muted" key={item.id} onClick={() => router.push("/records")}>
                <span className="min-w-0">
                  <strong className="block truncate text-sm">{item.course_code} · {item.section_code}</strong>
                  <span className="block truncate text-xs text-muted-foreground">{item.present} of {item.expected} present</span>
                </span>
                <ArrowRight className="size-4 shrink-0 text-muted-foreground" />
              </button>
            )) : <p className="py-8 text-center text-sm text-muted-foreground">Completed sessions will appear here.</p>}
          </CardContent>
        </Card>
      </section>

      <Card>
        <SectionHeading title="Today's teaching plan" description="Start attendance directly from a scheduled class." action={<StatusBadge tone={online ? "success" : "warning"}>{online ? "Live sync ready" : "Saved schedule"}</StatusBadge>} />
        <ClassList items={classes} />
      </Card>

      <Card>
        <SectionHeading title="Assigned courses" description="Courses and sections available to your institutional account." action={<Button variant="ghost" size="sm" onClick={() => router.push("/classes")}>View all<ArrowRight data-icon="inline-end" /></Button>} />
        <CourseGrid />
      </Card>
    </>
  );
}
