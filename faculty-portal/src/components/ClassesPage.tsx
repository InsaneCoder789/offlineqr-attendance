"use client";

import { ClassList } from "./ClassList";
import { CourseGrid } from "./CourseGrid";
import { useFacultyPortal } from "./FacultyPortalProvider";

export function ClassesPage() {
  const { classes, facultyCourses } = useFacultyPortal();
  const ready = classes.filter((item) => item.offline_ready).length;

  return (
    <>
      <section className="class-overview">
        <article>
          <span>Today</span>
          <strong>{classes.length}</strong>
          <p>{ready} offline-ready classes</p>
        </article>
        <article>
          <span>Sections</span>
          <strong>{new Set(facultyCourses.map((item) => item.section_code)).size}</strong>
          <p>Assigned to this account</p>
        </article>
        <article>
          <span>Courses</span>
          <strong>{facultyCourses.length}</strong>
          <p>Available for attendance</p>
        </article>
      </section>
      <section className="panel">
        <div className="section-head">
          <div>
            <h2>Today's classes</h2>
            <p>Assigned teaching schedule. Available offline when synced.</p>
          </div>
        </div>
        <ClassList items={classes} />
      </section>
      <section className="panel">
        <div className="section-head">
          <div>
            <h2>Course catalog</h2>
            <p>Start attendance, inspect sections, or open a register from one place.</p>
          </div>
        </div>
        <CourseGrid showActions />
      </section>
    </>
  );
}
