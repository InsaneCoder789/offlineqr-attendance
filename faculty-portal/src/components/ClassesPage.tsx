"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { BookOpen, CalendarDays, CalendarX2, Clock3, DoorOpen, Layers3, Play, Radio, WifiOff } from "lucide-react";
import { formatTime, stateClass, stateLabel } from "@/lib/format";
import { CourseGrid } from "./CourseGrid";
import { usePortalData } from "./FacultyPortalProvider";
import { ErrorPanel, PageIntro } from "./PortalUI";
import { StatePanel } from "./StatePanel";
import styles from "./ops.module.css";

type Tab = "today" | "courses";

function TimelineSkeleton() {
  return (
    <div role="status" aria-busy="true" style={{ display: "grid", gap: "0.9rem" }}>
      <span className="sr-only">Loading classes</span>
      {Array.from({ length: 3 }, (_, index) => <div key={index} className={styles.skel} style={{ height: "6.5rem" }} />)}
    </div>
  );
}

export function ClassesPage() {
  const router = useRouter();
  const { classes, facultyCourses, error, online, refresh, session, start, loading } = usePortalData();
  const [tab, setTab] = useState<Tab>("today");
  const [starting, setStarting] = useState<string | null>(null);
  const startInFlight = useRef(false);
  const tabRefs = useRef<Array<HTMLButtonElement | null>>([]);
  const ready = classes.filter((item) => item.offline_ready).length;
  const sections = new Set(facultyCourses.map((item) => item.section_code)).size;
  const tabs: Array<{ id: Tab; label: string }> = [{ id: "today", label: "Today" }, { id: "courses", label: "Courses" }];

  async function startAttendance(offeringId: string) {
    if (startInFlight.current) return;
    startInFlight.current = true;
    setStarting(offeringId);
    try {
      if (await start(offeringId)) router.push("/attendance");
    } finally {
      startInFlight.current = false;
      setStarting(null);
    }
  }

  const onTabKey = (event: React.KeyboardEvent, index: number) => {
    if (event.key !== "ArrowRight" && event.key !== "ArrowLeft") return;
    event.preventDefault();
    const next = (index + (event.key === "ArrowRight" ? 1 : tabs.length - 1)) % tabs.length;
    setTab(tabs[next].id);
    tabRefs.current[next]?.focus();
  };

  return (
    <div className={styles.scope}>
      <PageIntro eyebrow="Teaching schedule" title="Classes" description="Start a live session from today's timeline or open an assigned course." />
      {!online || error ? <ErrorPanel className="m-0" title={online ? "Some class data is unavailable" : "You are offline"} message={error ?? "Showing the last synchronized timetable."} onRetry={() => void refresh()} /> : null}
      <section className={styles.tiles} aria-label="Summary">
        {[
          { label: "Classes today", value: classes.length, icon: CalendarDays, detail: `${ready} offline-ready` },
          { label: "Sections", value: sections, icon: Layers3, detail: "Assigned to you" },
          { label: "Courses", value: facultyCourses.length, icon: BookOpen, detail: "Open for attendance" },
        ].map(({ label, value, icon: Icon, detail }) => (
          <article key={label} className={`${styles.glass} ${styles.tile}`}>
            <span className={styles.tileLabel}><Icon aria-hidden="true" />{label}</span>
            <strong className={`${styles.figure} ${styles.tileValue}`}>{value}</strong>
            <span className={styles.tileDetail}>{detail}</span>
          </article>
        ))}
      </section>

      <div className={styles.tabs} role="tablist" aria-label="Classes view">
        {tabs.map((item, index) => (
          <button key={item.id} ref={(node) => { tabRefs.current[index] = node; }} type="button" role="tab" id={`classes-tab-${item.id}`} aria-selected={tab === item.id} aria-controls={`classes-panel-${item.id}`} tabIndex={tab === item.id ? 0 : -1} className={styles.tab} onClick={() => setTab(item.id)} onKeyDown={(event) => onTabKey(event, index)}>{item.label}</button>
        ))}
      </div>

      {tab === "today" ? (
        <section role="tabpanel" id="classes-panel-today" aria-labelledby="classes-tab-today" style={{ minWidth: 0 }}>
          {classes.length === 0 && loading ? <TimelineSkeleton /> : classes.length === 0 ? (
            <StatePanel icon={CalendarX2} title="No classes scheduled today" text="Your synchronized teaching timetable will appear here." />
          ) : (
            <ol className={styles.timeline}>
              {classes.map((item, index) => {
                const live = Boolean(session && !session.closed_at && session.course_offering_id === item.course_offering_id);
                const offlineSession = live && session?.offline_pending_activation;
                const otherActive = Boolean(session && !session.closed_at && !live);
                const tone = stateClass(item, session);
                const label = stateLabel(item, session);
                const state = live ? "live" : label === "Now" ? "now" : label === "Completed" ? "done" : "next";
                return (
                  <li key={`${item.course_offering_id}:${item.start_time}:${item.end_time}:${index}`} className={styles.tlItem} data-state={state}>
                    <div className={styles.tlTime}><span>{formatTime(item.start_time)}</span><span className={styles.tlDot} aria-hidden="true" /><span style={{ color: "var(--muted-foreground)", fontWeight: 500 }}>{formatTime(item.end_time)}</span></div>
                    <article className={`${styles.glass} ${styles.tlCard}`}>
                      <div style={{ display: "grid", gridTemplateColumns: "minmax(0, 1fr)", gap: "0.5rem", minWidth: 0 }}>
                        <div className={styles.tlHead}>
                          <h3 className={styles.tlTitle}>{item.course_name}</h3>
                          <span className={styles.pill} data-tone={tone === "success" ? "ok" : tone === "warning" ? "warn" : undefined}>{live ? <Radio aria-hidden="true" /> : null}{offlineSession ? "Offline attendance" : label}</span>
                        </div>
                        <p className={styles.tlMeta}>
                          <span className="min-w-0 [overflow-wrap:anywhere]">{item.course_code} · {item.section_code}</span>
                          <span className="min-w-0 items-start!"><DoorOpen className="mt-0.5 shrink-0" aria-hidden="true" /><span className="block! min-w-0 [overflow-wrap:anywhere]">Room {item.room}</span></span>
                          <span><Clock3 aria-hidden="true" /><time>{formatTime(item.start_time)} - {formatTime(item.end_time)}</time></span>
                          {!item.offline_ready ? <span><WifiOff aria-hidden="true" />Not offline-ready</span> : null}
                        </p>
                      </div>
                      <button
                        type="button"
                        className={styles.ctaBtn}
                        data-variant={live ? "ghost" : undefined}
                        disabled={!live && (otherActive || starting !== null)}
                        title={otherActive ? "Close the active session first" : undefined}
                        onClick={() => live ? router.push("/attendance") : void startAttendance(item.course_offering_id)}
                      >
                        {live ? <Radio aria-hidden="true" /> : <Play aria-hidden="true" />}
                        {live ? (offlineSession ? "Open offline attendance" : "Open live attendance") : starting === item.course_offering_id ? "Starting…" : "Start attendance"}
                      </button>
                    </article>
                  </li>
                );
              })}
            </ol>
          )}
        </section>
      ) : (
        <section role="tabpanel" id="classes-panel-courses" aria-labelledby="classes-tab-courses" style={{ minWidth: 0 }}>
          <CourseGrid showActions />
        </section>
      )}
    </div>
  );
}
