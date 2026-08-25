"use client";

import { useRouter } from "next/navigation";
import { useFacultyPortal } from "./FacultyPortalProvider";
import { Icon } from "./Icons";

export function CourseGrid({ showActions = false }: { showActions?: boolean }) {
  const router = useRouter();
  const { facultyCourses, refreshRegister, start } = useFacultyPortal();

  if (facultyCourses.length === 0) {
    return (
      <div className="empty compact">
        <Icon name="classes" />
        <h3>No assigned courses synced</h3>
        <p>Sync to load your teaching assignments.</p>
      </div>
    );
  }

  return (
    <div className="course-grid">
      {facultyCourses.map((course) => (
        <article className="course-card" key={course.course_offering_id}>
          <div>
            <span>{course.course_code} | {course.section_code}</span>
            <strong>{course.course_name}</strong>
          </div>
          <p>{course.schedule_summary}</p>
          <footer>
            <small>{course.student_count} students</small>
            {showActions ? (
              <div className="course-actions">
                <button
                  className="secondary"
                  onClick={() => {
                    router.push("/records");
                    void refreshRegister(course.course_offering_id);
                  }}
                >
                  <Icon name="records" />
                  Register
                </button>
                <button onClick={async () => {
                  if (await start(course.course_offering_id)) router.push("/attendance");
                }}>
                  <Icon name="play" />
                  Start
                </button>
              </div>
            ) : null}
          </footer>
        </article>
      ))}
    </div>
  );
}
