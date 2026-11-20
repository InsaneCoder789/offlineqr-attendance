"use client";

import { useState } from "react";
import { AlertTriangle, CalendarRange, Download, Gauge, RefreshCw, Search, Users } from "lucide-react";
import { dateLabel, titleCase } from "@/lib/format";
import { usePortalData } from "./FacultyPortalProvider";
import { defaultThresholdPercent, usePortalUiActions, useRegisterFilters } from "./PortalUiState";
import { downloadBelowThresholdCsv, isBelowThreshold, normalizeThreshold, studentsBelowThreshold } from "@/lib/register-export";
import { ErrorPanel, PageIntro } from "./PortalUI";
import { initials, ProgressRing, useChunked } from "./LiveWidgets";
import { StatePanel } from "./StatePanel";
import styles from "./ops.module.css";
import { Button } from "./ui/button";
import { Select, SelectContent, SelectGroup, SelectItem, SelectTrigger, SelectValue } from "./ui/select";

const CHUNK = 50;

function toneFor(percentage: number, low: boolean): "ok" | "warn" | "bad" {
  if (low) return percentage < 50 ? "bad" : "warn";
  return "ok";
}

function RecordsSkeleton() {
  return (
    <div role="status" aria-busy="true" style={{ display: "grid", gap: "0.6rem", padding: "1rem" }}>
      <span className="sr-only">Loading register</span>
      {Array.from({ length: 7 }, (_, index) => <div key={index} className={styles.skel} style={{ height: "3.2rem" }} />)}
    </div>
  );
}

export function RecordsPage() {
  const { exportRegisterCsv, facultyCourses, loading, error, online, register, refreshRegister, selectedRegisterOfferingId } = usePortalData();
  const { registerDateFilter, registerQuery, thresholdPercent } = useRegisterFilters();
  const { setRegisterDateFilter, setRegisterQuery, setThresholdPercent } = usePortalUiActions();
  const [exportError, setExportError] = useState(false);

  const selected = selectedRegisterOfferingId ?? facultyCourses[0]?.course_offering_id ?? "";
  const visibleRegister = selected === register?.course_offering_id ? register : null;
  const courseOptions = facultyCourses.map((course) => ({
    value: course.course_offering_id,
    label: `${course.course_code} · ${course.section_code}`,
  }));
  const sessionOptions = [
    { value: "all", label: "All sessions" },
    ...(visibleRegister?.sessions ?? []).map((item) => ({ value: item.id, label: item.label })),
  ];
  const sessionFilter = sessionOptions.some((item) => item.value === registerDateFilter) ? registerDateFilter : "all";
  const belowThreshold = visibleRegister ? studentsBelowThreshold(visibleRegister, thresholdPercent) : [];
  const rated = visibleRegister?.students.filter((student) => student.present + student.absent > 0) ?? [];
  const average = rated.length ? Math.round(rated.reduce((sum, student) => sum + student.percentage, 0) / rated.length) : 0;
  const canExport = Boolean(!loading && visibleRegister && visibleRegister.sessions.length > 0);

  const runExport = () => {
    if (!canExport) return;
    setExportError(false);
    try {
      exportRegisterCsv();
    } catch {
      setExportError(true);
    }
  };

  return (
    <div className={`${styles.scope} ${styles.recordsScope}`}>
      <PageIntro
        eyebrow="Academic records"
        title={visibleRegister ? `${visibleRegister.course_code} · ${visibleRegister.section_code}` : "Attendance records"}
        description={visibleRegister ? visibleRegister.course_name : "Select an assigned course to inspect its attendance register."}
        actions={
          <button type="button" className={styles.ctaBtn} disabled={!canExport} onClick={runExport}>
            <Download aria-hidden="true" />Export CSV
          </button>
        }
      />

      {exportError ? <p role="alert" className="text-sm text-destructive">Could not export this register. Try again.</p> : null}

      <div className={styles.filterBar} role="search" aria-label="Register filters">
        <div className={styles.field}>
          <label className={styles.fieldLabel} id="reg-course-label" htmlFor="reg-course">Course</label>
          <Select items={courseOptions} value={selected || null} disabled={loading || courseOptions.length === 0} onValueChange={(value) => {
            if (!value || value === selected) return;
            setRegisterDateFilter("all");
            void refreshRegister(value);
          }}>
            <SelectTrigger id="reg-course" aria-labelledby="reg-course-label" className={styles.filterControl}>
              <SelectValue placeholder="No courses" />
            </SelectTrigger>
            <SelectContent align="start" alignItemWithTrigger={false}>
              <SelectGroup>
                {courseOptions.map((item) => <SelectItem key={item.value} value={item.value}>{item.label}</SelectItem>)}
              </SelectGroup>
            </SelectContent>
          </Select>
        </div>
        <div className={styles.field}>
          <label className={styles.fieldLabel} id="reg-session-label" htmlFor="reg-session">Session</label>
          <Select items={sessionOptions} value={sessionFilter} disabled={loading || sessionOptions.length === 1} onValueChange={(value) => {
            if (value) setRegisterDateFilter(value);
          }}>
            <SelectTrigger id="reg-session" aria-labelledby="reg-session-label" className={styles.filterControl}>
              <SelectValue />
            </SelectTrigger>
            <SelectContent align="start" alignItemWithTrigger={false}>
              <SelectGroup>
                {sessionOptions.map((item) => <SelectItem key={item.value} value={item.value}>{item.label}</SelectItem>)}
              </SelectGroup>
            </SelectContent>
          </Select>
        </div>
        <div className={`${styles.field} ${styles.studentFilter}`}>
          <label className={styles.fieldLabel} htmlFor="reg-search">Student</label>
          <div className={styles.search}>
            <Search aria-hidden="true" />
            <input id="reg-search" type="search" className={styles.searchInput} value={registerQuery} placeholder="Roll number or name" onChange={(event) => setRegisterQuery(event.target.value)} />
          </div>
        </div>
        <div className={styles.field}>
          <label className={styles.fieldLabel} htmlFor="attendance-threshold">Threshold %</label>
          <input id="attendance-threshold" className={styles.numInput} type="number" inputMode="decimal" min={0} max={100} step={1} value={thresholdPercent} onChange={(event) => setThresholdPercent(normalizeThreshold(Number(event.target.value), defaultThresholdPercent))} />
        </div>
        <Button variant="outline" className={styles.refreshFilter} disabled={!selected || loading || !online} onClick={() => selected && void refreshRegister(selected)}>
          <RefreshCw className={loading ? styles.spin : undefined} aria-hidden="true" />Refresh
        </Button>
      </div>

      {!online ? <ErrorPanel className="m-0" title="You are offline" message="Showing the last synchronized register. Refresh needs a connection." /> : error ? <ErrorPanel className="m-0" message={error} onRetry={selected && !loading ? () => void refreshRegister(selected) : undefined} /> : null}

      <section className={`${styles.tiles} ${styles.recordTiles}`} aria-label="Register summary">
        {[
          { label: "Enrolled", value: visibleRegister?.students.length ?? 0, icon: Users, detail: visibleRegister?.section_code ?? "No register selected" },
          { label: "Sessions", value: visibleRegister?.sessions.length ?? 0, icon: CalendarRange, detail: "Closed and synced" },
          { label: "Average", value: `${average}%`, icon: Gauge, detail: "Across students with sessions" },
          { label: `Below ${thresholdPercent}%`, value: belowThreshold.length, icon: AlertTriangle, detail: "Needs faculty review" },
        ].map(({ label, value, icon: Icon, detail }) => (
          <article key={label} className={`${styles.glass} ${styles.tile}`}>
            <span className={styles.tileLabel}><Icon aria-hidden="true" />{label}</span>
            <strong className={`${styles.figure} ${styles.tileValue}`}>{value}</strong>
            <span className={styles.tileDetail}>{detail}</span>
          </article>
        ))}
      </section>

      {visibleRegister ? (
        <>
          <RiskList />
          <RegisterGrid sessionFilter={sessionFilter} />
        </>
      ) : loading ? (
        <section className={styles.glass}><RecordsSkeleton /></section>
      ) : (
        <StatePanel icon={CalendarRange} title="No register loaded" text="Select an assigned course to load its synchronized attendance records." />
      )}
      <SessionLedger />
    </div>
  );
}

function RiskList() {
  const { register } = usePortalData();
  const { thresholdPercent } = useRegisterFilters();
  if (!register) return null;
  const students = studentsBelowThreshold(register, thresholdPercent);
  return (
    <section className={styles.glass} aria-label="Attendance risk">
      <div className={styles.sectionHead}>
        <div>
          <h3 className={styles.sectionTitle}>Attendance risk</h3>
          <p className={styles.sectionSub}>Students below {thresholdPercent}%. Students with no recorded sessions are not counted.</p>
        </div>
        <button type="button" className={styles.ctaBtn} data-variant="ghost" disabled={students.length === 0} onClick={() => downloadBelowThresholdCsv(register, thresholdPercent)}>
          <Download aria-hidden="true" />Below-threshold CSV
        </button>
      </div>
      {students.length === 0 ? (
        <p className={styles.hint}>No students below threshold. Everyone with recorded attendance is at or above {thresholdPercent}%.</p>
      ) : (
        <>
          <ul className={styles.risk}>
            {students.slice(0, 12).map((student) => (
              <li key={student.student_id} className={styles.riskItem}>
                <ProgressRing value={student.percentage} max={100} size={52} stroke={12} tone={toneFor(student.percentage, true)} label={`${student.percentage.toFixed(0)} percent`}>
                  <span className={styles.barNum} style={{ fontSize: "0.7rem" }}>{student.percentage.toFixed(0)}</span>
                </ProgressRing>
                <div className={styles.riskBody}>
                  <strong className={styles.nameCol}>{student.display_name}</strong>
                  <span className={styles.mono} style={{ color: "var(--muted-foreground)" }}>{student.roll_number} · P {student.present} / A {student.absent}</span>
                </div>
              </li>
            ))}
          </ul>
          {students.length > 12 ? <p className={styles.hint}>Showing the first 12 of {students.length}. The CSV includes every student below the threshold.</p> : null}
        </>
      )}
    </section>
  );
}

function RegisterGrid({ sessionFilter }: { sessionFilter: string }) {
  const { register } = usePortalData();
  const { registerQuery, thresholdPercent } = useRegisterFilters();
  const normalizedQuery = registerQuery.trim().toLowerCase();
  const matching = register ? register.students.filter((student) => !normalizedQuery || student.roll_number.toLowerCase().includes(normalizedQuery) || student.display_name.toLowerCase().includes(normalizedQuery)) : [];
  const { count, hasMore, sentinelRef, more } = useChunked(matching.length, CHUNK, `${normalizedQuery}|${sessionFilter}|${register?.course_offering_id}`);
  if (!register) return null;
  const sessions = sessionFilter === "all" ? register.sessions : register.sessions.filter((item) => item.id === sessionFilter);
  const shown = matching.slice(0, count);
  const label = `${register.course_code} ${register.section_code} attendance register`;

  return (
    <section className={styles.glass} aria-label={label}>
      <div className={styles.sectionHead}>
        <div>
          <h3 className={styles.sectionTitle}>Attendance register</h3>
          <p className={styles.sectionSub}>{matching.length} of {register.students.length} students · {sessions.length} {sessions.length === 1 ? "session" : "sessions"}</p>
        </div>
      </div>
      {register.sessions.length === 0 ? (
        <div style={{ padding: "0 1rem 1rem" }}><StatePanel icon={CalendarRange} title="No sessions conducted" text="The register populates after a session is closed and synchronized." /></div>
      ) : shown.length === 0 ? (
        <div style={{ padding: "0 1rem 1rem" }}><StatePanel icon={Search} title="No matching students" text="Clear the search or change the session filter." /></div>
      ) : (
        <>
          <div className={styles.legend} aria-hidden="true">
            <span><i style={{ background: "var(--o-ok)" }} />Present</span>
            <span><i style={{ background: "var(--o-bad)" }} />Absent</span>
            <span><i style={{ background: "var(--o-hair)" }} />Not held</span>
          </div>
          <div className={styles.tableWrap} role="region" aria-label={`${label} table`} tabIndex={0}>
            <table className={styles.grid}>
              <thead>
                <tr>
                  <th scope="col" className={styles.stuCell}>Student</th>
                  <th scope="col">Attendance</th>
                  <th scope="col">Present</th>
                  <th scope="col">Absent</th>
                  <th scope="col">Sessions</th>
                </tr>
              </thead>
              <tbody>
                {shown.map((student) => {
                  const low = isBelowThreshold(student, thresholdPercent);
                  const tone = toneFor(student.percentage, low);
                  return (
                    <tr key={student.student_id} data-low={low || undefined} data-below-threshold={low || undefined}>
                      <td className={styles.stuCell}>
                        <div className={styles.cellStudent}>
                          <span className={styles.avatar} aria-hidden="true">{initials(student.display_name)}</span>
                          <div style={{ minWidth: 0 }}><strong className={styles.mono} style={{ display: "block" }}>{student.roll_number}</strong><span className={styles.nameCol} style={{ fontSize: "0.78rem", color: "var(--muted-foreground)", fontWeight: 400 }}>{student.display_name}</span></div>
                        </div>
                      </td>
                      <td>
                        <div className={styles.bar}>
                          <span className={styles.barNum}>{student.percentage.toFixed(0)}%{low ? <span className="sr-only"> (below {thresholdPercent}% threshold)</span> : null}</span>
                          <div className={styles.barTrack} aria-hidden="true"><div className={styles.barFill} data-tone={tone} style={{ width: `${Math.max(0, Math.min(100, student.percentage))}%` }} /></div>
                        </div>
                      </td>
                      <td className="tabular-nums">{student.present}</td>
                      <td className="tabular-nums">{student.absent}</td>
                      <td>
                        <div className={styles.heat} role="img" aria-label={`${student.present} present, ${student.absent} absent across ${sessions.length} sessions`}>
                          {sessions.map((item) => {
                            const status = student.statuses[item.id];
                            return <span key={item.id} className={styles.heatCell} data-s={status ?? "NONE"} title={`${item.label} · ${dateLabel(new Date(item.scheduled_start))} · ${status ? titleCase(status) : "Not recorded"}`} />;
                          })}
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
          {hasMore ? (
            <>
              <div key={count} ref={sentinelRef} className={styles.sentinel} aria-hidden="true" />
              <button type="button" className={styles.more} onClick={more}>Show more ({matching.length - count} remaining)</button>
            </>
          ) : null}
          <p className={styles.listFoot}>Showing {shown.length} of {matching.length}. The CSV export includes the complete filtered register.</p>
        </>
      )}
    </section>
  );
}

function SessionLedger() {
  const { sessionHistory } = usePortalData();
  const records = sessionHistory.slice(0, 12);
  return (
    <section className={styles.glass} aria-label="Session ledger">
      <div className={styles.sectionHead}>
        <div>
          <h3 className={styles.sectionTitle}>Session ledger</h3>
          <p className={styles.sectionSub}>Recent attendance sessions from courses assigned to you.</p>
        </div>
      </div>
      {records.length === 0 ? <p className={styles.hint}>No sessions available. Completed sessions appear here after synchronization.</p> : (
        <div className={styles.tableWrap} role="region" aria-label="Session ledger table" tabIndex={0}>
          <table className={styles.grid}>
            <thead><tr><th scope="col">Date</th><th scope="col">Course</th><th scope="col">State</th><th scope="col" className={styles.alignRight}>Present</th></tr></thead>
            <tbody>
              {records.map((row) => (
                <tr key={row.id}>
                  <td>{dateLabel(new Date(row.scheduled_start))}</td>
                  <td className={styles.nameCol}>{row.course_code} · {row.section_code}</td>
                  <td><span className={styles.pill} data-tone={row.state === "ACTIVE" ? "ok" : undefined}>{titleCase(row.state)}</span></td>
                  <td className={`${styles.alignRight} tabular-nums`}>{row.present} / {row.expected}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}
