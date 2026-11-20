"use client";

import { AlertTriangle, CalendarRange, Download, RefreshCw, Search, Users } from "lucide-react";
import { dateLabel, titleCase } from "@/lib/format";
import { usePortalData } from "./FacultyPortalProvider";
import { defaultThresholdPercent, usePortalUiActions, useRegisterFilters } from "./PortalUiState";
import { downloadBelowThresholdCsv, isBelowThreshold, normalizeThreshold, studentsBelowThreshold } from "@/lib/register-export";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectGroup, SelectItem, SelectTrigger } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { EmptyPanel, ErrorPanel, LoadingPanel, MetricStrip, PageIntro, SectionHeading, StatusBadge, useMinWidth } from "./PortalUI";

export function RecordsPage() {
  const { exportRegisterCsv, facultyCourses, loading, error, online, register, refreshRegister, selectedRegisterOfferingId } = usePortalData();
  const { registerDateFilter, registerQuery, thresholdPercent } = useRegisterFilters();
  const { setRegisterDateFilter, setRegisterQuery, setThresholdPercent } = usePortalUiActions();

  const selected = selectedRegisterOfferingId ?? facultyCourses.find((item) => item.section_code === "CS21")?.course_offering_id ?? facultyCourses[0]?.course_offering_id ?? "";
  const selectedCourse = facultyCourses.find((item) => item.course_offering_id === selected);
  const visibleRegister = selected === register?.course_offering_id ? register : null;
  const belowThreshold = visibleRegister ? studentsBelowThreshold(visibleRegister, thresholdPercent) : [];

  return (
    <>
      <PageIntro
        eyebrow="Academic records"
        title={visibleRegister ? `${visibleRegister.course_code} · ${visibleRegister.section_code} register` : "Attendance records"}
        description={visibleRegister ? visibleRegister.course_name : "Select an assigned course to inspect its authoritative attendance register."}
        actions={<Button variant="outline" disabled={!visibleRegister} onClick={exportRegisterCsv}><Download data-icon="inline-start" />Export CSV</Button>}
      />

      {!online ? <ErrorPanel className="m-0" title="You are offline" message="Showing the last synchronized register. Refresh needs a connection." /> : error ? <ErrorPanel className="m-0" message={error} onRetry={() => selected && void refreshRegister(selected)} /> : null}
      <MetricStrip className="xl:grid-cols-3" metrics={[
        { label: "Enrolled students", value: visibleRegister?.students.length ?? 0, icon: Users, detail: visibleRegister?.section_code ?? "No register selected" },
        { label: "Closed sessions", value: visibleRegister?.sessions.length ?? 0, icon: CalendarRange, detail: "Included in this register" },
        { label: `Below ${thresholdPercent}%`, value: belowThreshold.length, icon: AlertTriangle, detail: "Requires faculty review" },
      ]} />

      <section className="dashboard-canvas overflow-clip rounded-xl bg-card">
        <SectionHeading title="Register filters" description="Choose a course, narrow the roster, and inspect a specific session." />
        <div className="sticky top-[4.5rem] z-10 grid gap-3 border-b bg-card/95 p-4 backdrop-blur sm:p-5 md:grid-cols-2 xl:grid-cols-[minmax(13rem,0.8fr)_minmax(15rem,1fr)_minmax(12rem,0.7fr)_minmax(8rem,0.4fr)_auto]">
          <Select value={selected} onValueChange={(value) => { setRegisterDateFilter("all"); if (value) void refreshRegister(value); }}>
            <SelectTrigger className="h-10 w-full" aria-label="Select course register"><span className="truncate text-left">{selectedCourse ? `${selectedCourse.course_code} · ${selectedCourse.section_code}` : "Select course"}</span></SelectTrigger>
            <SelectContent><SelectGroup>{facultyCourses.map((course) => <SelectItem key={course.course_offering_id} value={course.course_offering_id}>{course.course_code} · {course.section_code}</SelectItem>)}</SelectGroup></SelectContent>
          </Select>
          <div className="relative">
            <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
            <Input type="search" value={registerQuery} placeholder="Search roll number or name" aria-label="Search register by roll number or name" className="pl-9" onChange={(event) => setRegisterQuery(event.target.value)} />
          </div>
          <Select value={registerDateFilter} disabled={!visibleRegister?.sessions.length} onValueChange={(value) => value && setRegisterDateFilter(value)}>
            <SelectTrigger className="h-10 w-full" aria-label="Filter by session"><span className="truncate text-left">{registerDateFilter === "all" ? "All sessions" : visibleRegister?.sessions.find((item) => item.id === registerDateFilter)?.label ?? "All sessions"}</span></SelectTrigger>
            <SelectContent><SelectGroup><SelectItem value="all">All sessions</SelectItem>{(visibleRegister?.sessions ?? []).map((item) => <SelectItem key={item.id} value={item.id}>{item.label}</SelectItem>)}</SelectGroup></SelectContent>
          </Select>
          <div className="flex items-center gap-2">
            <label htmlFor="attendance-threshold" className="shrink-0 text-xs font-medium text-muted-foreground">Threshold %</label>
            <Input
              id="attendance-threshold"
              type="number"
              inputMode="decimal"
              min={0}
              max={100}
              step={1}
              value={thresholdPercent}
              className="h-10 w-full"
              onChange={(event) => setThresholdPercent(normalizeThreshold(Number(event.target.value), defaultThresholdPercent))}
            />
          </div>
          <Button variant="outline" className="max-sm:w-full" disabled={!selected} onClick={() => selected && void refreshRegister(selected)}><RefreshCw data-icon="inline-start" />Refresh</Button>
        </div>
        {visibleRegister ? <RegisterPanel /> : loading ? <LoadingPanel rows={5} label="Loading register" /> : <EmptyPanel icon={CalendarRange} title="No register loaded" description="Select an assigned course to load its synchronized attendance records." />}
        {visibleRegister ? <BelowThresholdPanel /> : null}
        <SessionLedger />
      </section>
    </>
  );
}

function RegisterPanel() {
  const wide = useMinWidth(768);
  const { register } = usePortalData();
  const { registerDateFilter, registerQuery, thresholdPercent } = useRegisterFilters();
  if (!register) return null;
  const normalizedQuery = registerQuery.trim().toLowerCase();
  const sessions = registerDateFilter === "all" ? register.sessions : register.sessions.filter((item) => item.id === registerDateFilter);
  const matchingStudents = register.students.filter((student) => !normalizedQuery || student.roll_number.toLowerCase().includes(normalizedQuery) || student.display_name.toLowerCase().includes(normalizedQuery));
  const shownStudents = matchingStudents.slice(0, wide ? 80 : 60);

  return (
    <section className="min-w-0 border-t border-border/60">
      <SectionHeading title={`${register.course_code} attendance register`} description={`${register.course_name} · ${register.section_code} · ${matchingStudents.length} of ${register.students.length} students`} action={<StatusBadge>{sessions.length} sessions</StatusBadge>} />
      {register.sessions.length === 0 ? <EmptyPanel icon={CalendarRange} title="No sessions conducted" description="The register populates after a session is closed and synchronized." className="m-5" /> : shownStudents.length === 0 ? <EmptyPanel icon={Search} title="No matching students" description="Clear the search or change the session filter." className="m-5" /> : (
        <>
          {!wide ? (
            <ul className="grid gap-2 p-3" aria-label={`${register.course_code} ${register.section_code} attendance register`}>
              {shownStudents.map((student) => {
                const low = isBelowThreshold(student, thresholdPercent);
                return (
                  <li key={student.student_id} data-below-threshold={low || undefined} className={`flex min-w-0 items-center justify-between gap-3 rounded-lg border p-3 [contain-intrinsic-size:auto_4.5rem] [content-visibility:auto] ${low ? "border-warning/50 bg-warning/10" : "bg-card"}`}>
                    <div className="min-w-0"><strong className="block break-words text-sm font-medium">{student.display_name}</strong><span className="font-mono text-xs text-muted-foreground">{student.roll_number}</span><span className="mt-1 block text-xs text-muted-foreground">Present {student.present} · Absent {student.absent}</span></div>
                    <StatusBadge tone={low ? "warning" : "success"} icon={low ? AlertTriangle : undefined}>{student.percentage.toFixed(0)}%{low ? <span className="sr-only"> (below {thresholdPercent}% threshold)</span> : null}</StatusBadge>
                  </li>
                );
              })}
            </ul>
          ) : (
          <div className="max-w-full overflow-auto" role="region" aria-label={`${register.course_code} ${register.section_code} attendance register`}>
            <Table className="min-w-max">
              <TableHeader>
                <TableRow>
                  <TableHead className="sticky left-0 min-w-56 bg-card">Roll / student</TableHead>
                  {sessions.map((item) => <TableHead className="text-center" key={item.id} title={`${dateLabel(new Date(item.scheduled_start))} · ${titleCase(item.state)}`}>{item.label}</TableHead>)}
                  <TableHead className="text-center">Present</TableHead>
                  <TableHead className="text-center">Absent</TableHead>
                  <TableHead className="text-center">Rate</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {shownStudents.map((student) => {
                  const low = isBelowThreshold(student, thresholdPercent);
                  return (
                  <TableRow key={student.student_id} data-below-threshold={low || undefined} className={low ? "bg-amber-500/10" : undefined}>
                    <TableCell className={low ? "sticky left-0 bg-amber-50 dark:bg-amber-950" : "sticky left-0 bg-card"}><strong className="block font-mono text-xs">{student.roll_number}</strong><span className="mt-0.5 block text-xs text-muted-foreground">{student.display_name}</span></TableCell>
                    {sessions.map((item) => <RegisterMark key={item.id} status={student.statuses[item.id]} />)}
                    <TableCell className="text-center">{student.present}</TableCell>
                    <TableCell className="text-center">{student.absent}</TableCell>
                    <TableCell className="text-center"><StatusBadge tone={low ? "warning" : "success"} icon={low ? AlertTriangle : undefined}>{student.percentage.toFixed(0)}%{low ? <span className="sr-only"> (below {thresholdPercent}% threshold)</span> : null}</StatusBadge></TableCell>
                  </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </div>
          )}
          {matchingStudents.length > shownStudents.length ? <p className="border-t px-5 py-3 text-xs text-muted-foreground">Showing the first {shownStudents.length} matching students. The CSV export includes the complete filtered register.</p> : null}
        </>
      )}
    </section>
  );
}

function RegisterMark({ status }: { status: string | null }) {
  return <TableCell className="text-center"><StatusBadge tone={status === "PRESENT" ? "success" : status === "ABSENT" ? "error" : "neutral"}>{status === "PRESENT" ? "P" : status === "ABSENT" ? "A" : "-"}</StatusBadge></TableCell>;
}

function BelowThresholdPanel() {
  const { register } = usePortalData();
  const { thresholdPercent } = useRegisterFilters();
  if (!register) return null;
  const students = studentsBelowThreshold(register, thresholdPercent);
  return (
    <section className="border-t border-border/60">
      <SectionHeading
        title="Attendance risk"
        description={`Students below ${thresholdPercent}% attendance for this course. Students with no recorded sessions are not counted.`}
        action={
          <div className="flex flex-wrap items-center gap-2">
            <StatusBadge tone={students.length ? "warning" : "success"}>{students.length} students</StatusBadge>
            <Button variant="outline" size="sm" disabled={students.length === 0} onClick={() => downloadBelowThresholdCsv(register, thresholdPercent)}>
              <Download data-icon="inline-start" />Download below-threshold CSV
            </Button>
          </div>
        }
      />
      {students.length === 0 ? <EmptyPanel icon={Users} title="No students below threshold" description={`Every student with recorded attendance is at or above ${thresholdPercent}%.`} className="m-5" /> : (
        <>
          <div className="max-w-full overflow-x-auto"><Table><TableHeader><TableRow><TableHead scope="col">Roll number</TableHead><TableHead scope="col">Student</TableHead><TableHead scope="col">Present</TableHead><TableHead scope="col">Absent</TableHead><TableHead scope="col" className="text-right">Rate</TableHead></TableRow></TableHeader><TableBody>{students.slice(0, 10).map((student) => <TableRow key={student.student_id}><TableCell className="font-mono text-xs">{student.roll_number}</TableCell><TableCell className="font-medium">{student.display_name}</TableCell><TableCell>{student.present}</TableCell><TableCell>{student.absent}</TableCell><TableCell className="text-right"><StatusBadge tone="warning" icon={AlertTriangle}>{student.percentage.toFixed(0)}%</StatusBadge></TableCell></TableRow>)}</TableBody></Table></div>
          {students.length > 10 ? <p className="border-t px-5 py-3 text-xs text-muted-foreground">Showing the first 10 of {students.length}. The CSV includes every student below the threshold.</p> : null}
        </>
      )}
    </section>
  );
}

function SessionLedger() {
  const { sessionHistory } = usePortalData();
  const records = sessionHistory.slice(0, 12);
  return (
    <section className="border-t border-border/60">
      <SectionHeading title="Session ledger" description="Recent attendance sessions from courses assigned to this faculty account." />
      {records.length === 0 ? <EmptyPanel icon={CalendarRange} title="No sessions available" description="Completed sessions appear here after synchronization." className="m-5" /> : (
        <div className="overflow-x-auto"><Table><TableHeader><TableRow><TableHead>Date</TableHead><TableHead>Course</TableHead><TableHead>State</TableHead><TableHead className="text-right">Present</TableHead></TableRow></TableHeader><TableBody>{records.map((row) => <TableRow key={row.id}><TableCell>{dateLabel(new Date(row.scheduled_start))}</TableCell><TableCell className="font-medium">{row.course_code} · {row.section_code}</TableCell><TableCell><StatusBadge tone={row.state === "ACTIVE" ? "success" : "neutral"}>{titleCase(row.state)}</StatusBadge></TableCell><TableCell className="text-right">{row.present} / {row.expected}</TableCell></TableRow>)}</TableBody></Table></div>
      )}
    </section>
  );
}
