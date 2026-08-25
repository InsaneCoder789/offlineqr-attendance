"use client";

import { presentCount } from "../lib/format";
import { useFacultyPortal } from "./FacultyPortalProvider";
import { Icon } from "./Icons";
import { QrPanel } from "./QrPanel";
import { RosterTable } from "./RosterTable";

export function AttendancePage() {
  const {
    roster,
    rosterFilter,
    rosterQuery,
    session,
    setRosterFilter,
    setRosterQuery,
  } = useFacultyPortal();

  if (!session) {
    return (
      <section className="empty">
        <Icon name="attendance" />
        <h2>No active attendance session</h2>
        <p>Navigate to Dashboard or My Classes and tap Start Attendance to begin.</p>
      </section>
    );
  }

  return (
    <section className="attendance-layout">
      <QrPanel />
      <section className="panel">
        <div className="section-head">
          <div>
            <h2>Student Roster</h2>
            <p>{presentCount(roster)} of {roster.length} present</p>
          </div>
        </div>
        <div className="roster-tools">
          <input
            type="search"
            value={rosterQuery}
            placeholder="Search roll number or name"
            aria-label="Search roster"
            onChange={(event) => setRosterQuery(event.target.value)}
          />
          <div className="segmented" aria-label="Roster filter">
            <button className={`secondary ${rosterFilter === "all" ? "active" : ""}`} onClick={() => setRosterFilter("all")}>All</button>
            <button className={`secondary ${rosterFilter === "present" ? "active" : ""}`} onClick={() => setRosterFilter("present")}>Present</button>
            <button className={`secondary ${rosterFilter === "pending" ? "active" : ""}`} onClick={() => setRosterFilter("pending")}>Not recorded</button>
          </div>
        </div>
        <RosterTable />
      </section>
    </section>
  );
}
