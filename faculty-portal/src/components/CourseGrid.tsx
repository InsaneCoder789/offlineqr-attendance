"use client";

import { useRouter } from "next/navigation";
import { ArrowRight, BookOpen, ClipboardList, GraduationCap, Play } from "lucide-react";
import { usePortalData } from "./FacultyPortalProvider";
import { Button } from "@/components/ui/button";
import { Card, CardAction, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card";
import { EmptyPanel, LoadingPanel } from "./PortalUI";

export function CourseGrid({ showActions = false }: { showActions?: boolean }) {
  const router = useRouter();
  const { facultyCourses, refreshRegister, start, loading } = usePortalData();

  if (facultyCourses.length === 0 && loading) return <LoadingPanel rows={3} label="Loading courses" />;
  if (facultyCourses.length === 0) {
    return <EmptyPanel icon={BookOpen} title="No assigned courses" description="Course assignments will appear after the next successful synchronization." className="m-5" />;
  }

  return (
    <div className="grid gap-4 p-5 sm:grid-cols-2 2xl:grid-cols-3">
      {facultyCourses.map((course, index) => (
        <Card key={`${course.course_offering_id}:${course.section_code}:${index}`} className="bg-muted/35 shadow-none! transition-colors hover:bg-muted/65">
          <CardHeader>
            <CardTitle className="pr-16">{course.course_name}</CardTitle>
            <CardDescription>{course.course_code} · Section {course.section_code}</CardDescription>
            <CardAction><span className="flex size-9 items-center justify-center rounded-lg bg-primary/10 text-primary"><GraduationCap className="size-4" /></span></CardAction>
          </CardHeader>
          <CardContent>
            <p className="text-sm leading-6 text-muted-foreground">{course.schedule_summary}</p>
          </CardContent>
          <CardFooter className="flex-wrap justify-between gap-3">
            <span className="text-xs font-medium text-muted-foreground">{course.student_count} students</span>
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
          </CardFooter>
        </Card>
      ))}
    </div>
  );
}
