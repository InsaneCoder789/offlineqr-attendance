"use client";

import { useRouter } from "next/navigation";
import { ArrowRight, BookOpen, ClipboardList, GraduationCap, Play, Users } from "lucide-react";
import { usePortalData } from "./FacultyPortalProvider";
import { Button } from "@/components/ui/button";
import { courseAccentStyle, EmptyPanel, ErrorPanel, LoadingPanel } from "./PortalUI";

export function CourseGrid({ showActions = false, limit }: { showActions?: boolean; limit?: number }) {
  const router = useRouter();
  const { facultyCourses, refreshRegister, start, loading, error, refresh } = usePortalData();

  if (facultyCourses.length === 0 && loading) return <LoadingPanel rows={3} label="Loading courses" />;
  if (facultyCourses.length === 0 && error) return <ErrorPanel message={error} onRetry={() => void refresh()} />;
  if (facultyCourses.length === 0) {
    return <EmptyPanel icon={BookOpen} title="No assigned courses" description="Course assignments will appear after the next successful synchronization." className="m-5" />;
  }

  const courses = typeof limit === "number" ? facultyCourses.slice(0, limit) : facultyCourses;

  return (
    <div className="grid gap-4 p-4 sm:grid-cols-2 sm:p-5 xl:grid-cols-3">
      {courses.map((course, index) => (
        <article
          key={`${course.course_offering_id}:${course.section_code}:${index}`}
          className="course-accent enter group relative flex min-w-0 flex-col gap-4 overflow-hidden rounded-3xl border border-border bg-foreground/[0.025] p-5 transition-colors hover:bg-foreground/[0.05]"
          style={courseAccentStyle(course.course_code)}
        >
          <span className="bar-accent-course absolute inset-x-5 top-0 h-0.5 rounded-b-full" aria-hidden="true" />
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0">
              <p className="text-accent-course text-xs font-bold tracking-wide">{course.course_code} · Section {course.section_code}</p>
              <h4 className="mt-1.5 text-balance text-base font-bold leading-snug tracking-tight">{course.course_name}</h4>
            </div>
            <span className="bg-accent-course-soft text-accent-course flex size-10 shrink-0 items-center justify-center rounded-2xl"><GraduationCap className="size-5" aria-hidden="true" /></span>
          </div>
          <p className="text-sm leading-6 text-muted-foreground">{course.schedule_summary}</p>
          <div className="mt-auto flex flex-wrap items-center justify-between gap-3">
            <span className="flex items-center gap-1.5 text-xs font-semibold text-muted-foreground"><Users className="size-3.5" aria-hidden="true" />{course.student_count} students</span>
            {showActions ? (
              <div className="flex flex-wrap items-center gap-2">
                <Button variant="outline" size="sm" onClick={() => {
                  router.push("/records");
                  void refreshRegister(course.course_offering_id);
                }}>
                  <ClipboardList data-icon="inline-start" />Register
                </Button>
                <Button size="sm" onClick={async () => {
                  if (await start(course.course_offering_id)) router.push("/attendance");
                }}>
                  <Play data-icon="inline-start" />Start
                </Button>
              </div>
            ) : <Button variant="ghost" size="sm" onClick={() => router.push("/classes")}>View course<ArrowRight data-icon="inline-end" /></Button>}
          </div>
        </article>
      ))}
    </div>
  );
}
