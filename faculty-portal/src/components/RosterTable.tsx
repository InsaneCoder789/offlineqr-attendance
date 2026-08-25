"use client";

import { rosterStatus } from "../lib/format";
import { useFacultyPortal } from "./FacultyPortalProvider";
import { Icon } from "./Icons";

export function RosterTable() {
  const { roster, rosterFilter, rosterQuery, setConfirmStudent } = useFacultyPortal();
  const normalizedQuery = rosterQuery.trim().toLowerCase();
  const filtered = roster.filter((student) => {
    const isPresent = student.attendance_status === "PRESENT";
    const matchesFilter =
      rosterFilter === "all" ||
      (rosterFilter === "present" && isPresent) ||
      (rosterFilter === "pending" && !isPresent);
    const matchesQuery =
      !normalizedQuery ||
      student.roll_number.toLowerCase().includes(normalizedQuery) ||
      student.display_name.toLowerCase().includes(normalizedQuery);
    return matchesFilter && matchesQuery;
  });

  if (roster.length === 0) {
    return (
      <div className="empty compact">
        <Icon name="records" />
        <h3>Roster unavailable</h3>
        <p>Try syncing when the backend is reachable.</p>
      </div>
    );
  }

  if (filtered.length === 0) {
    return (
      <div className="empty compact">
        <Icon name="records" />
        <h3>No matching students</h3>
        <p>Clear the search or switch the roster filter.</p>
      </div>
    );
  }

  return (
    <div className="roster-table">
      <div className="table-head">
        <span>Roll No.</span>
        <span>Student</span>
        <span>Status</span>
        <span>Action</span>
      </div>
      {filtered.map((student) => {
        const isPresent = student.attendance_status === "PRESENT";
        const status = rosterStatus(student);
        return (
          <div className="table-row" key={student.student_id}>
            <span>{student.roll_number}</span>
            <strong>{student.display_name}</strong>
            <span className={`status ${status.tone}`}>{status.label}</span>
            <button
              className="secondary"
              disabled={isPresent}
              aria-label={isPresent ? `${student.display_name} is already present` : `Mark ${student.display_name} as present`}
              onClick={() => setConfirmStudent(student)}
            >
              <Icon name="check" />
              {isPresent ? "Recorded" : "Mark Present"}
            </button>
          </div>
        );
      })}
    </div>
  );
}
