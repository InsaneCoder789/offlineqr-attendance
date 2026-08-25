"use client";

import type { FacultyClass } from "../api";
import { useRouter } from "next/navigation";
import { formatTime, stateClass, stateLabel } from "../lib/format";
import { useFacultyPortal } from "./FacultyPortalProvider";
import { Icon } from "./Icons";

export function ClassList({ items }: { items: FacultyClass[] }) {
  const router = useRouter();
  const { session, start } = useFacultyPortal();

  if (items.length === 0) {
    return (
      <div className="empty compact">
        <Icon name="classes" />
        <h3>No classes scheduled for today</h3>
        <p>Sync to load your timetable from the server.</p>
      </div>
    );
  }

  return (
    <div className="class-list">
      {items.map((item) => (
        <article className="class-row" key={item.course_offering_id}>
          <time>{formatTime(item.start_time)} - {formatTime(item.end_time)}</time>
          <div className="class-row-details">
            <strong>{item.course_name}</strong>
            <p className="class-meta">
              <span className="class-room"><Icon name="room" />Room {item.room}</span>
              <span className="class-separator">|</span>
              <span className="class-code">{item.course_code} | {item.section_code}</span>
            </p>
          </div>
          <span className={`status ${stateClass(item, session)}`}>{stateLabel(item, session)}</span>
          <button
            disabled={Boolean(session && !session.closed_at && session.course_offering_id !== item.course_offering_id)}
            title={session && !session.closed_at && session.course_offering_id !== item.course_offering_id ? "Close the active session first" : undefined}
            onClick={async () => {
              if (await start(item.course_offering_id)) router.push("/attendance");
            }}
          >
            <Icon name="play" />
            Start Attendance
          </button>
        </article>
      ))}
    </div>
  );
}
