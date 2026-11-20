"use client";

import { BookOpen, CalendarDays, Layers3, WifiOff } from "lucide-react";
import { ClassList } from "./ClassList";
import { CourseGrid } from "./CourseGrid";
import { usePortalData } from "./FacultyPortalProvider";
import { ErrorPanel, MetricStrip, PageIntro, SectionHeading, StatusBadge } from "./PortalUI";

export function ClassesPage() {
  const { classes, facultyCourses, error, online, refresh } = usePortalData();
  const ready = classes.filter((item) => item.offline_ready).length;
  const sections = new Set(facultyCourses.map((item) => item.section_code)).size;

  return (
    <>
      <PageIntro
        eyebrow="Teaching schedule"
        title="Classes and course assignments"
        description="Review today's timetable, open a live session, or access an assigned course register."
      />
      {!online || error ? <ErrorPanel className="m-0" title={online ? "Some class data is unavailable" : "You are offline"} message={error ?? "Showing the last synchronized timetable."} onRetry={() => void refresh()} /> : null}
      <MetricStrip className="xl:grid-cols-3" metrics={[
        { label: "Classes today", value: classes.length, icon: CalendarDays, detail: `${ready} offline-ready` },
        { label: "Assigned sections", value: sections, icon: Layers3, detail: "Authorized for this account" },
        { label: "Course offerings", value: facultyCourses.length, icon: BookOpen, detail: "Available for attendance" },
      ]} />
      <section className="dashboard-canvas overflow-hidden rounded-xl bg-card">
        <SectionHeading title="Today's classes" description="The synchronized teaching plan remains available during a network interruption." action={<StatusBadge tone={ready === classes.length ? "success" : "warning"} icon={ready === classes.length ? undefined : WifiOff}>{ready}/{classes.length} offline-ready</StatusBadge>} />
        <ClassList items={classes} />
        <div className="border-t border-border/60">
          <SectionHeading title="Course catalog" description="Start attendance or open the course register from a verified assignment." />
          <CourseGrid showActions />
        </div>
      </section>
    </>
  );
}
