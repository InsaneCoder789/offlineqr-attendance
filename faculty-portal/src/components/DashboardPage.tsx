"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { ArrowRight, CalendarDays, QrCode } from "lucide-react";
import type { FacultyClass } from "@/api";
import { formatTime, minutes, presentCount } from "@/lib/format";
import { Button } from "@/components/ui/button";
import { usePortalData } from "./FacultyPortalProvider";
import styles from "./dashboard.module.css";

const timeZone = process.env.NEXT_PUBLIC_INSTITUTION_TIMEZONE || "Asia/Kolkata";
const clock = new Intl.DateTimeFormat("en-GB", { timeZone, hour: "2-digit", minute: "2-digit", hourCycle: "h23" });
const dayKey = new Intl.DateTimeFormat("en-CA", { timeZone, dateStyle: "short" });
const dayLabel = new Intl.DateTimeFormat("en-IN", { timeZone, weekday: "long", day: "numeric", month: "long" });

export function DashboardPage() {
  const router = useRouter();
  const {
    classes, facultyCourses, facultyIdentity, register, roster, session,
    sessionHistory, online, start, loading, error, refresh,
  } = usePortalData();
  const [now, setNow] = useState<Date | null>(null);
  const [starting, setStarting] = useState<string | null>(null);
  const startInFlight = useRef(false);

  useEffect(() => {
    const update = () => setNow(new Date());
    const initial = window.setTimeout(update, 0);
    const interval = window.setInterval(update, 15_000);
    return () => {
      window.clearTimeout(initial);
      window.clearInterval(interval);
    };
  }, []);

  const active = session && !session.closed_at ? session : null;
  const sorted = [...classes].sort((a, b) => minutes(a.start_time) - minutes(b.start_time));
  const currentMinute = now ? minutes(clock.format(now)) : -1;
  const ongoing = now ? sorted.find((item) => minutes(item.start_time) <= currentMinute && currentMinute < minutes(item.end_time)) : undefined;
  const next = now ? sorted.find((item) => minutes(item.start_time) > currentMinute) : undefined;
  const focusClass = active ?? ongoing ?? next;
  const courseSize = focusClass ? facultyCourses.find((course) => course.course_offering_id === focusClass.course_offering_id)?.student_count : undefined;
  const ongoingStartUnavailable = Boolean(ongoing && !online && !ongoing.offline_ready);
  const pastSessions = sessionHistory
    .filter((item) => item.state === "CLOSED")
    .sort((a, b) => Date.parse(b.scheduled_start) - Date.parse(a.scheduled_start));
  const closedToday = now ? pastSessions.filter((item) => dayKey.format(new Date(item.scheduled_start)) === dayKey.format(now)).length : null;
  const pending = roster.filter((student) => student.attendance_status !== "PRESENT" && student.claim_state === "PROOF_READY").length;
  const measured = register?.students.filter((student) => student.present + student.absent > 0) ?? [];
  const atRisk = measured.filter((student) => student.percentage < 75).sort((a, b) => a.percentage - b.percentage);
  const busy = loading || starting !== null;
  const hasSnapshot = Boolean(classes.length || facultyCourses.length || sessionHistory.length || active);
  const waiting = loading && !hasSnapshot;
  const unavailable = !hasSnapshot && Boolean(error || !online);

  async function openSession(item: FacultyClass) {
    if (startInFlight.current || loading || active || (!online && !item.offline_ready)) return;
    startInFlight.current = true;
    setStarting(item.course_offering_id);
    try {
      if (await start(item.course_offering_id)) router.push("/attendance");
    } finally {
      startInFlight.current = false;
      setStarting(null);
    }
  }

  return (
    <div className={styles.dashboard}>
      <header className={styles.masthead}>
        <div>
          <p className={styles.caption} suppressHydrationWarning>{now ? dayLabel.format(now) : "Faculty preview"}</p>
          <h2>Teaching desk</h2>
          {facultyIdentity?.display_name && <p className={styles.byline}>{facultyIdentity.display_name}</p>}
        </div>
        <Link className={styles.textLink} href="/records">Attendance records <ArrowRight size={16} aria-hidden="true" /></Link>
      </header>

      {error ? (
        <div className={styles.notice}>
          <p>Refresh the preview to retry loading workspace data.</p>
          <Button size="sm" variant="outline" disabled={busy} onClick={() => void refresh()}>{loading && !starting ? "Refreshing…" : "Retry refresh"}</Button>
        </div>
      ) : null}

      <div className={styles.workspace}>
        <section className={styles.plan} aria-labelledby="teaching-plan">
          <div className={styles.sectionHead}>
            <h3 id="teaching-plan">Today’s teaching plan</h3>
            <Link className={styles.textLink} href="/classes">My classes <ArrowRight size={16} aria-hidden="true" /></Link>
          </div>

          {focusClass && (
            <section className={styles.live} aria-label="Class summary">
              <div>
                <p className={styles.caption}>{active ? (active.offline_pending_activation ? "Offline attendance session" : "Attendance session open") : ongoing ? "Ongoing class" : "Next class"}</p>
                <h4>{focusClass.course_name}</h4>
                <p>{focusClass.course_code} · {focusClass.section_code}{focusClass.room ? ` · Room ${focusClass.room}` : ""}</p>
                <p>{active
                  ? `${clock.format(new Date(active.scheduled_start))}–${clock.format(new Date(active.scheduled_end))}`
                  : ongoing ? `${formatTime(ongoing.start_time)}–${formatTime(ongoing.end_time)}` : next ? `${formatTime(next.start_time)}–${formatTime(next.end_time)}` : ""}</p>
                <p role="status">{active
                  ? (roster.length ? `${presentCount(roster)} / ${roster.length} present · ${pending} proofs pending` : "Roster unavailable")
                  : [courseSize === undefined ? "" : `${courseSize} enrolled`, ongoingStartUnavailable ? "Attendance unavailable offline" : "Attendance not started"].filter(Boolean).join(" · ")}</p>
              </div>
              {active
                ? <Button onClick={() => router.push("/attendance")}><QrCode aria-hidden="true" /> Open attendance</Button>
                : ongoing && !ongoingStartUnavailable ? (
                  <Button disabled={busy} onClick={() => void openSession(ongoing)}>
                    {starting === ongoing.course_offering_id ? "Starting…" : online ? "Start attendance" : "Start offline"}
                  </Button>
                ) : null}
            </section>
          )}

          {sorted.length ? (
            <ol className={styles.schedule}>
              {sorted.map((item, index) => {
                const isActive = active?.course_offering_id === item.course_offering_id;
                const ended = minutes(item.end_time) <= currentMinute;
                const inProgress = minutes(item.start_time) <= currentMinute && !ended;
                const needsPreparation = !online && !item.offline_ready;
                const isStarting = starting === item.course_offering_id;
                const status = isActive ? "Attendance open" : ended ? "Time elapsed" : inProgress ? "Class in progress" : item === next ? "Up next" : "Scheduled";
                return (
                  <li key={`${item.course_offering_id}:${item.start_time}:${index}`} data-highlight={isActive || (!active && item === (ongoing ?? next))}>
                    <div className={styles.time}><strong>{formatTime(item.start_time)}</strong><span>{formatTime(item.end_time)}</span></div>
                    <div className={styles.classInfo}>
                      <p className={styles.caption}>{status}</p>
                      <h4>{item.course_name}</h4>
                      <p>{item.course_code} · {item.section_code}{item.room ? ` · Room ${item.room}` : ""}</p>
                    </div>
                    <div className={styles.rowAction}>
                      {isActive ? (
                        <Link className={styles.textLink} href="/attendance">Open roster <ArrowRight size={16} aria-hidden="true" /></Link>
                      ) : ended ? null : active ? (
                        <span>Another session is open</span>
                      ) : needsPreparation ? (
                        <span>Unavailable offline</span>
                      ) : (
                        <Button size="sm" variant={item === (ongoing ?? next) ? "default" : "outline"} disabled={busy} onClick={() => void openSession(item)}>
                          {isStarting ? "Starting…" : online ? "Start attendance" : "Start offline"}
                        </Button>
                      )}
                    </div>
                  </li>
                );
              })}
            </ol>
          ) : (
            <div className={styles.empty} role={waiting ? "status" : undefined}>
              <CalendarDays size={22} aria-hidden="true" />
              <p>{waiting ? "Loading today’s classes…" : unavailable ? "Today’s schedule is unavailable." : "No classes scheduled today."}</p>
            </div>
          )}
          {!!facultyCourses.length && <p className={styles.assignment}>{facultyCourses.length} assigned {facultyCourses.length === 1 ? "course" : "courses"} <Link className={styles.textLink} href="/classes">View courses <ArrowRight size={16} aria-hidden="true" /></Link></p>}
        </section>

        <aside className={styles.review} aria-labelledby="attendance-review">
          <h3 id="attendance-review">Attendance review</h3>
          <dl className={styles.metrics}>
            <div><dt>Sessions closed today</dt><dd>{waiting || unavailable ? "—" : closedToday ?? "—"}</dd></div>
            <div><dt>Live roster proofs pending</dt><dd>{active && roster.length ? pending : "—"}</dd></div>
            <div><dt>Below 75%{register ? ` · ${register.course_code}` : ""}</dt><dd>{measured.length ? atRisk.length : "—"}</dd></div>
          </dl>
          {!measured.length && <p className={styles.note}>{register ? "This register has no recorded attendance yet." : "Select a course register in Records to see attendance risk."}</p>}
          {!!atRisk.length && <ul className={styles.risk}>{atRisk.slice(0, 5).map((student) => <li key={student.student_id}><span>{student.display_name}</span><strong>{Math.round(student.percentage)}%</strong></li>)}</ul>}

          <div className={styles.recent}>
            <h4>Recently closed</h4>
            {pastSessions.length ? (
              <ul>{pastSessions.slice(0, 4).map((record) => (
                <li key={record.id}>
                  <span><strong>{record.course_code} · {record.section_code}</strong><small>{dayLabel.format(new Date(record.scheduled_start))}</small></span>
                  <span>{record.present} / {record.expected} present</span>
                </li>
              ))}</ul>
            ) : <p className={styles.note}>{waiting ? "Loading session history…" : unavailable ? "Session history is unavailable." : "No closed sessions to review."}</p>}
          </div>
        </aside>
      </div>
    </div>
  );
}
