"use client";

import { useRouter } from "next/navigation";
import { dayPart, formatTime, isSameDay, minutes, presentCount } from "../lib/format";
import { ClassList } from "./ClassList";
import { CourseGrid } from "./CourseGrid";
import { useFacultyPortal } from "./FacultyPortalProvider";
import { Icon } from "./Icons";

export function DashboardPage() {
  const router = useRouter();
  const { classes, facultyCourses, facultyIdentity, register, roster, session, sessionHistory, online, start } = useFacultyPortal();
  const activeSession = session && !session.closed_at ? session : null;
  const nowMinutes = new Date().getHours() * 60 + new Date().getMinutes();
  const next = classes.find((item) => minutes(item.end_time) >= nowMinutes) ?? null;
  const completedToday = sessionHistory.filter((item) => isSameDay(new Date(item.scheduled_start), new Date()) && item.state === "CLOSED").length;
  const offlineReady = classes.filter((item) => item.offline_ready).length;
  const pendingRoster = activeSession ? Math.max(0, roster.length - presentCount(roster)) : 0;
  const pendingSync = activeSession ? pendingRoster : classes.filter((item) => !item.offline_ready).length;
  const belowThreshold = register
    ? register.students.filter((student) => student.present + student.absent > 0 && student.percentage < 75).length
    : 0;
  const recent = sessionHistory.slice(0, 3);

  return (
    <>
      <section className="faculty-hero">
        <div>
          <p className="eyeline">Faculty workspace</p>
          <h2>Good {dayPart()}, {facultyIdentity?.display_name ?? "Faculty"}</h2>
          <p>Manage today's teaching plan, start classroom QR attendance, review live rosters, and recover offline submissions from one console.</p>
          <div className="hero-actions">
            <button onClick={() => router.push("/classes")}><Icon name="classes" />Open classes</button>
            {next ? <button onClick={async () => {
              if (await start(next.course_offering_id)) router.push("/attendance");
            }}><Icon name="play" />Quick start next class</button> : null}
            <button className="secondary" onClick={() => router.push("/records")}><Icon name="records" />Review records</button>
          </div>
        </div>
        <div className="faculty-hero-card">
          <span>{activeSession ? "Live now" : "Next class"}</span>
          <strong>{activeSession ? `${activeSession.course_code} | ${activeSession.section_code}` : next ? `${formatTime(next.start_time)} | ${next.course_code}` : "No more classes"}</strong>
          <p>{activeSession
            ? `${activeSession.course_name} | ${activeSession.room ?? "Room TBC"} | ${presentCount(roster)} of ${roster.length} present`
            : next ? `${next.course_name} | ${next.section_code} | Room ${next.room}` : "Your remaining teaching schedule is clear for today."}</p>
          {activeSession ? <button onClick={() => router.push("/attendance")}><Icon name="attendance" />Open live session</button> : next ? <button onClick={async () => {
            if (await start(next.course_offering_id)) router.push("/attendance");
          }}><Icon name="play" />Start now</button> : null}
        </div>
      </section>
      <section className="metrics">
        <Metric label="Classes today" value={String(classes.length)} icon="classes" />
        <Metric label="Pending sync" value={String(pendingSync)} icon={online ? "refresh" : "wifiOff"} />
        <Metric label="Students in register" value={String(register?.students.length ?? 0)} icon="records" />
        <Metric label="Attendance risk" value={String(belowThreshold)} icon="alert" />
      </section>
      <section className="ops-grid">
        <article className={`ops-card ${activeSession ? "active" : ""}`}>
          <span>Active classroom</span>
          <strong>{activeSession ? activeSession.course_name : "No live session"}</strong>
          <p>{activeSession ? `${activeSession.section_code} | ${activeSession.room ?? "Room TBC"} | QR rotates every 5 seconds` : "Start attendance from today's teaching plan when class begins."}</p>
        </article>
        <article className="ops-card">
          <span>Offline readiness</span>
          <strong>{offlineReady}/{classes.length || 0} ready</strong>
          <p>{online ? "Today’s schedule and active session state are cached locally." : "Offline mode is active. Existing live QR sessions continue from local session state."}</p>
        </article>
        <article className="ops-card">
          <span>Recently completed</span>
          <strong>{completedToday}</strong>
          <p>{recent.length ? recent.map((item) => `${item.course_code} ${item.present}/${item.expected}`).join(" | ") : "Closed sessions appear here after attendance is ended."}</p>
        </article>
      </section>
      {activeSession ? (
        <section className="session-strip">
          <div>
            <span className="status success">Attendance Active</span>
            <strong>{activeSession.course_name}</strong>
            <p>{activeSession.section_code} | {activeSession.room ?? "Room TBC"} | {presentCount(roster)} of {roster.length} recorded</p>
          </div>
          <button onClick={() => router.push("/attendance")}><Icon name="attendance" />Open Live Session</button>
        </section>
      ) : null}
      <section className="panel">
        <div className="section-head">
          <div>
            <h2>Today's Teaching Plan</h2>
            <p>Start attendance directly from your scheduled classes.</p>
          </div>
          <span className="status neutral">{online ? "Live sync ready" : "Saved schedule"}</span>
        </div>
        <ClassList items={classes} />
      </section>
      <section className="panel">
        <div className="section-head">
          <div>
            <h2>Assigned Sections</h2>
            <p>Courses currently available to this faculty account.</p>
          </div>
        </div>
        <CourseGrid />
      </section>
    </>
  );
}

function Metric({ label, value, icon }: { label: string; value: string; icon: Parameters<typeof Icon>[0]["name"] }) {
  return (
    <article className="metric">
      <span className="metric-label"><span className="metric-icon"><Icon name={icon} /></span>{label}</span>
      <strong>{value}</strong>
    </article>
  );
}
