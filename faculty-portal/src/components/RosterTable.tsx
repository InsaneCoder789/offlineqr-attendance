"use client";

import { Check, CheckCircle2, CircleDashed, ClipboardList, Clock3, ShieldCheck, UserCheck } from "lucide-react";
import type { RosterStudent } from "@/api";
import { rosterStatus } from "@/lib/format";
import { usePortalData } from "./FacultyPortalProvider";
import { usePortalUiActions, useRosterFilters } from "./PortalUiState";
import { useMinWidth } from "./PortalUI";
import { Button } from "./ui/button";
import { initials, useChunked } from "./LiveWidgets";
import { StatePanel } from "./StatePanel";
import styles from "./ops.module.css";

const CHUNK = 60;

function StatusPill({ student }: { student: RosterStudent }) {
  const status = rosterStatus(student);
  const attested = student.attendance_method === "FACULTY_ATTESTATION" && student.attendance_status === "PRESENT";
  const Icon = attested ? ShieldCheck : status.tone === "success" ? CheckCircle2 : status.tone === "warning" ? Clock3 : CircleDashed;
  return <span className={styles.pill} data-tone={status.tone === "success" ? "ok" : status.tone === "warning" ? "warn" : status.tone === "error" ? "bad" : undefined}><Icon aria-hidden="true" />{status.label}</span>;
}

function RosterSkeleton() {
  return (
    <div role="status" aria-busy="true" style={{ display: "grid", gap: "0.6rem", padding: "0.9rem" }}>
      <span className="sr-only">Loading roster</span>
      {Array.from({ length: 6 }, (_, index) => <div key={index} className={styles.skel} style={{ height: "3.2rem" }} />)}
    </div>
  );
}

export function RosterTable({ attestedOnly = false }: { attestedOnly?: boolean }) {
  const { roster, clearError, loading } = usePortalData();
  const wide = useMinWidth(1280);
  const { rosterFilter, rosterQuery } = useRosterFilters();
  const { setConfirmStudent } = usePortalUiActions();
  const normalizedQuery = rosterQuery.trim().toLowerCase();
  const filtered = roster.filter((student) => {
    const isPresent = student.attendance_status === "PRESENT";
    const matchesFilter = rosterFilter === "all" || (rosterFilter === "present" && isPresent) || (rosterFilter === "pending" && !isPresent);
    const matchesAttested = !attestedOnly || (isPresent && student.attendance_method === "FACULTY_ATTESTATION");
    const matchesQuery = !normalizedQuery || student.roll_number.toLowerCase().includes(normalizedQuery) || student.display_name.toLowerCase().includes(normalizedQuery);
    return matchesFilter && matchesAttested && matchesQuery;
  });
  const { count, hasMore, sentinelRef, more } = useChunked(filtered.length, CHUNK, `${rosterFilter}|${attestedOnly}|${normalizedQuery}`);

  if (roster.length === 0 && loading) return <RosterSkeleton />;
  if (roster.length === 0) return <div style={{ padding: "0.9rem" }}><StatePanel icon={ClipboardList} title="Roster unavailable" text="The enrolled student roster will appear after the session synchronizes." /></div>;
  if (filtered.length === 0) return <div style={{ padding: "0.9rem" }}><StatePanel icon={UserCheck} title="No matching students" text="Clear the search or change the roster filter." /></div>;

  const visible = filtered.slice(0, count);
  const presentTotal = roster.filter((student) => student.attendance_status === "PRESENT").length;
  const attest = (student: RosterStudent) => { clearError(); setConfirmStudent(student); };
  const labelFor = (student: RosterStudent) => student.attendance_status === "PRESENT"
    ? `${student.display_name}, roll ${student.roll_number}: attendance recorded`
    : `Attest ${student.display_name}, roll ${student.roll_number}, as present`;

  return (
    <div>
      <p role="status" aria-live="polite" aria-atomic="true" className="sr-only">Showing {filtered.length} of {roster.length} students. {presentTotal} marked present.</p>
      {!wide ? (
        <ul className={styles.cards}>
          {visible.map((student) => {
            const isPresent = student.attendance_status === "PRESENT";
            return (
              <li key={student.student_id} className={styles.rosterCardItem}>
                <div className={styles.rosterCardTop}>
                  <div className={styles.cellStudent}>
                    <span className={styles.avatar} aria-hidden="true">{initials(student.display_name)}</span>
                    <div style={{ minWidth: 0 }}><strong className={styles.nameCol} style={{ display: "block" }}>{student.display_name}</strong><span className={styles.mono} style={{ color: "var(--muted-foreground)" }}>{student.roll_number}</span></div>
                  </div>
                  <StatusPill student={student} />
                </div>
                {!isPresent && <Button type="button" variant="outline" size="sm" disabled={loading} aria-label={labelFor(student)} onClick={() => attest(student)}>
                  <Check aria-hidden="true" />Attest
                </Button>}
              </li>
            );
          })}
        </ul>
      ) : (
        <div className={styles.gridWrap} role="region" aria-label="Student roster table" tabIndex={0}>
          <table className={styles.grid}>
            <thead>
              <tr>
                <th scope="col">Roll number</th>
                <th scope="col">Student</th>
                <th scope="col">Status</th>
                <th scope="col" className={styles.alignRight}>Action</th>
              </tr>
            </thead>
            <tbody>
              {visible.map((student) => {
                const isPresent = student.attendance_status === "PRESENT";
                return (
                  <tr key={student.student_id}>
                    <td className={styles.mono}>{student.roll_number}</td>
                    <td><div className={styles.cellStudent}><span className={styles.avatar} aria-hidden="true">{initials(student.display_name)}</span><span className={styles.nameCol}>{student.display_name}</span></div></td>
                    <td><StatusPill student={student} /></td>
                    <td className={styles.alignRight}>
                      {!isPresent && <Button type="button" variant="outline" size="sm" disabled={loading} aria-label={labelFor(student)} onClick={() => attest(student)}>
                        <Check aria-hidden="true" />Attest
                      </Button>}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
      {hasMore ? (
        <>
          <div key={count} ref={sentinelRef} className={styles.sentinel} aria-hidden="true" />
          <button type="button" className={styles.more} onClick={more}>Show more ({filtered.length - count} remaining)</button>
        </>
      ) : null}
      <p className={styles.listFoot}>Showing {visible.length} of {filtered.length}{filtered.length !== roster.length ? ` (filtered from ${roster.length})` : ""}</p>
    </div>
  );
}
