"use client";

import { dateLabel, titleCase } from "../lib/format";
import { useFacultyPortal } from "./FacultyPortalProvider";
import { Icon } from "./Icons";

export function RecordsPage() {
  const {
    exportRegisterCsv,
    facultyCourses,
    register,
    registerDateFilter,
    registerQuery,
    refreshRegister,
    selectedRegisterOfferingId,
    sessionHistory,
    setRegisterDateFilter,
    setRegisterQuery,
  } = useFacultyPortal();

  const selected =
    selectedRegisterOfferingId ??
    facultyCourses.find((item) => item.section_code === "CS21")?.course_offering_id ??
    facultyCourses[0]?.course_offering_id ??
    "";
  const visibleRegister = selected === register?.course_offering_id ? register : null;
  const belowThreshold = visibleRegister
    ? visibleRegister.students.filter((student) => student.present + student.absent > 0 && student.percentage < 75)
    : [];
  const records = sessionHistory.slice(0, 12);

  return (
    <>
      <section className="records-hero">
        <div>
          <p className="eyeline">Teaching records</p>
          <h2>{visibleRegister ? `${visibleRegister.course_code} | ${visibleRegister.section_code}` : "Course Register"}</h2>
          <p>{visibleRegister ? visibleRegister.course_name : "Select a course to inspect its academic attendance register."}</p>
        </div>
        <div className="records-summary">
          <span><strong>{visibleRegister?.students.length ?? 0}</strong> Students</span>
          <span><strong>{visibleRegister?.sessions.length ?? 0}</strong> Closed Sessions</span>
          <span><strong>{belowThreshold.length}</strong> Below 75%</span>
        </div>
      </section>
      <div className="filters">
        <select aria-label="Select course register" value={selected} onChange={(event) => {
          setRegisterDateFilter("all");
          if (event.target.value) void refreshRegister(event.target.value);
        }}>
          {facultyCourses.map((course) => (
            <option key={course.course_offering_id} value={course.course_offering_id}>
              {course.course_code} | {course.section_code}
            </option>
          ))}
        </select>
        <button className="secondary" disabled={!selected} onClick={() => selected && void refreshRegister(selected)}>
          <Icon name="refresh" />
          Load Register
        </button>
        <input
          type="search"
          value={registerQuery}
          placeholder="Search roll number or name"
          aria-label="Search register"
          onChange={(event) => setRegisterQuery(event.target.value)}
        />
        <select
          aria-label="Filter register by session date"
          disabled={!visibleRegister?.sessions.length}
          value={registerDateFilter}
          onChange={(event) => setRegisterDateFilter(event.target.value)}
        >
          <option value="all">All sessions</option>
          {(visibleRegister?.sessions ?? []).map((item) => <option key={item.id} value={item.id}>{item.label}</option>)}
        </select>
        <button className="secondary" disabled={!visibleRegister} onClick={exportRegisterCsv}>
          <Icon name="records" />
          Export CSV
        </button>
      </div>
      {visibleRegister ? <RegisterPanel /> : (
        <section className="panel">
          <div className="empty compact">
            <Icon name="records" />
            <h3>No register loaded</h3>
            <p>Select a course and sync to load the attendance register.</p>
          </div>
        </section>
      )}
      {visibleRegister ? <BelowThresholdPanel /> : null}
      <section className="panel">
        <div className="section-head">
          <div>
            <h2>Session Ledger</h2>
            <p>Recent sessions from courses assigned to this faculty account.</p>
          </div>
        </div>
        {records.length === 0 ? (
          <div className="empty compact">
            <Icon name="records" />
            <h3>No records available yet</h3>
            <p>Completed sessions will appear here after syncing.</p>
          </div>
        ) : (
          <div className="roster-table">
            <div className="table-head">
              <span>Date</span>
              <span>Course</span>
              <span>Status</span>
              <span>Present</span>
            </div>
            {records.map((row) => (
              <div className="table-row" key={row.id}>
                <span>{dateLabel(new Date(row.scheduled_start))}</span>
                <strong>{row.course_code} | {row.section_code}</strong>
                <span className={`status ${row.state === "ACTIVE" ? "success" : "neutral"}`}>{titleCase(row.state)}</span>
                <span>{row.present} / {row.expected}</span>
              </div>
            ))}
          </div>
        )}
      </section>
    </>
  );
}

function RegisterPanel() {
  const { register, registerDateFilter, registerQuery } = useFacultyPortal();
  if (!register) return null;
  const normalizedQuery = registerQuery.trim().toLowerCase();
  const sessions = registerDateFilter === "all"
    ? register.sessions
    : register.sessions.filter((item) => item.id === registerDateFilter);
  const matchingStudents = register.students.filter((student) =>
    !normalizedQuery ||
    student.roll_number.toLowerCase().includes(normalizedQuery) ||
    student.display_name.toLowerCase().includes(normalizedQuery)
  );
  const shownStudents = matchingStudents.slice(0, 80);

  return (
    <section className="panel">
      <div className="section-head">
        <div>
          <h2>{register.course_code} Attendance Register</h2>
          <p>{register.course_name} | {register.section_code} | {matchingStudents.length} of {register.students.length} enrolled students</p>
        </div>
        <span className="status neutral">{sessions.length} sessions</span>
      </div>
      {register.sessions.length === 0 ? (
        <div className="empty compact">
          <Icon name="records" />
          <h3>No sessions conducted</h3>
          <p>The register will populate after attendance sessions are closed and synchronized.</p>
        </div>
      ) : shownStudents.length === 0 ? (
        <div className="empty compact">
          <Icon name="records" />
          <h3>No matching students</h3>
          <p>Clear the register search or change the session filter.</p>
        </div>
      ) : (
        <>
          <div className="register-scroll" role="region" aria-label={`${register.course_code} ${register.section_code} attendance register`}>
            <table className="register-table">
              <thead>
                <tr>
                  <th className="sticky-col">Roll / Student</th>
                  {sessions.map((item) => <th key={item.id} title={`${dateLabel(new Date(item.scheduled_start))} | ${titleCase(item.state)}`}>{item.label}</th>)}
                  <th>Present</th>
                  <th>Absent</th>
                  <th>%</th>
                </tr>
              </thead>
              <tbody>
                {shownStudents.map((student) => (
                  <tr key={student.student_id}>
                    <td className="sticky-col"><strong>{student.roll_number}</strong><span>{student.display_name}</span></td>
                    {sessions.map((item) => <RegisterMark key={item.id} status={student.statuses[item.id]} />)}
                    <td>{student.present}</td>
                    <td>{student.absent}</td>
                    <td><span className={`status ${student.percentage >= 75 ? "success" : "warning"}`}>{student.percentage.toFixed(0)}%</span></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {matchingStudents.length > shownStudents.length ? <p className="table-note">Showing first {shownStudents.length} matching students. Export CSV includes the filtered register view.</p> : null}
        </>
      )}
    </section>
  );
}

function RegisterMark({ status }: { status: string | null }) {
  if (status === "PRESENT") return <td><span className="mark present" title="Present">P</span></td>;
  if (status === "ABSENT") return <td><span className="mark absent" title="Absent">A</span></td>;
  return <td><span className="mark empty" title="No finalized record">-</span></td>;
}

function BelowThresholdPanel() {
  const { register } = useFacultyPortal();
  const students = register
    ? register.students.filter((student) => student.present + student.absent > 0 && student.percentage < 75)
    : [];

  return (
    <section className="panel">
      <div className="section-head">
        <div>
          <h2>Below Attendance Threshold</h2>
          <p>Students below the configured 75% attendance threshold for the selected course.</p>
        </div>
        <span className={`status ${students.length > 0 ? "warning" : "success"}`}>{students.length} students</span>
      </div>
      {students.length === 0 ? (
        <div className="empty compact">
          <Icon name="check" />
          <h3>No students below threshold</h3>
          <p>The selected course has no recorded students below 75%.</p>
        </div>
      ) : (
        <div className="roster-table compact-table">
          {students.slice(0, 10).map((student) => (
            <div className="table-row" key={student.student_id}>
              <span>{student.roll_number}</span>
              <strong>{student.display_name}</strong>
              <span>{student.present} P | {student.absent} A</span>
              <span className="status warning">{student.percentage.toFixed(0)}%</span>
            </div>
          ))}
        </div>
      )}
    </section>
  );
}
