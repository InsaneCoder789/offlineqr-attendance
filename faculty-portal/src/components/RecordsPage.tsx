"use client";

import { AlertTriangle, CalendarRange, Download, RefreshCw, Search, Users } from "lucide-react";
import { dateLabel, titleCase } from "@/lib/format";
import { useFacultyPortal } from "./FacultyPortalProvider";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectGroup, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { EmptyPanel, MetricStrip, PageIntro, SectionHeading, StatusBadge } from "./PortalUI";

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

  const selected = selectedRegisterOfferingId ?? facultyCourses.find((item) => item.section_code === "CS21")?.course_offering_id ?? facultyCourses[0]?.course_offering_id ?? "";
  const visibleRegister = selected === register?.course_offering_id ? register : null;
  const belowThreshold = visibleRegister ? visibleRegister.students.filter((student) => student.present + student.absent > 0 && student.percentage < 75) : [];

  return (
    <>
      <PageIntro
        eyebrow="Academic records"
        title={visibleRegister ? `${visibleRegister.course_code} · ${visibleRegister.section_code} register` : "Attendance records"}
        description={visibleRegister ? visibleRegister.course_name : "Select an assigned course to inspect its authoritative attendance register."}
        actions={<Button variant="outline" disabled={!visibleRegister} onClick={exportRegisterCsv}><Download data-icon="inline-start" />Export CSV</Button>}
      />

      <MetricStrip className="xl:grid-cols-3" metrics={[
        { label: "Enrolled students", value: visibleRegister?.students.length ?? 0, icon: Users, detail: visibleRegister?.section_code ?? "No register selected" },
        { label: "Closed sessions", value: visibleRegister?.sessions.length ?? 0, icon: CalendarRange, detail: "Included in this register" },
        { label: "Below 75%", value: belowThreshold.length, icon: AlertTriangle, detail: "Requires faculty review" },
      ]} />

      <Card>
        <SectionHeading title="Register filters" description="Choose a course, narrow the roster, and inspect a specific session." />
        <div className="grid gap-3 p-5 md:grid-cols-2 xl:grid-cols-[minmax(13rem,0.8fr)_minmax(15rem,1fr)_minmax(12rem,0.7fr)_auto]">
          <Select value={selected} onValueChange={(value) => { setRegisterDateFilter("all"); if (value) void refreshRegister(value); }}>
            <SelectTrigger className="h-10 w-full" aria-label="Select course register"><SelectValue placeholder="Select course" /></SelectTrigger>
            <SelectContent><SelectGroup>{facultyCourses.map((course) => <SelectItem key={course.course_offering_id} value={course.course_offering_id}>{course.course_code} · {course.section_code}</SelectItem>)}</SelectGroup></SelectContent>
          </Select>
          <div className="relative">
            <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
            <Input type="search" value={registerQuery} placeholder="Search roll number or name" className="pl-9" onChange={(event) => setRegisterQuery(event.target.value)} />
          </div>
          <Select value={registerDateFilter} disabled={!visibleRegister?.sessions.length} onValueChange={(value) => value && setRegisterDateFilter(value)}>
            <SelectTrigger className="h-10 w-full" aria-label="Filter by session"><SelectValue placeholder="All sessions" /></SelectTrigger>
            <SelectContent><SelectGroup><SelectItem value="all">All sessions</SelectItem>{(visibleRegister?.sessions ?? []).map((item) => <SelectItem key={item.id} value={item.id}>{item.label}</SelectItem>)}</SelectGroup></SelectContent>
          </Select>
          <Button variant="outline" disabled={!selected} onClick={() => selected && void refreshRegister(selected)}><RefreshCw data-icon="inline-start" />Refresh</Button>
        </div>
      </Card>

      {visibleRegister ? <RegisterPanel /> : <EmptyPanel icon={CalendarRange} title="No register loaded" description="Select an assigned course to load its synchronized attendance records." />}
      {visibleRegister ? <BelowThresholdPanel /> : null}
      <SessionLedger />
    </>
  );
}

function RegisterPanel() {
  const { register, registerDateFilter, registerQuery } = useFacultyPortal();
  if (!register) return null;
  const normalizedQuery = registerQuery.trim().toLowerCase();
  const sessions = registerDateFilter === "all" ? register.sessions : register.sessions.filter((item) => item.id === registerDateFilter);
  const matchingStudents = register.students.filter((student) => !normalizedQuery || student.roll_number.toLowerCase().includes(normalizedQuery) || student.display_name.toLowerCase().includes(normalizedQuery));
  const shownStudents = matchingStudents.slice(0, 80);

  return (
    <Card className="min-w-0">
      <SectionHeading title={`${register.course_code} attendance register`} description={`${register.course_name} · ${register.section_code} · ${matchingStudents.length} of ${register.students.length} students`} action={<StatusBadge>{sessions.length} sessions</StatusBadge>} />
      {register.sessions.length === 0 ? <EmptyPanel icon={CalendarRange} title="No sessions conducted" description="The register populates after a session is closed and synchronized." className="m-5" /> : shownStudents.length === 0 ? <EmptyPanel icon={Search} title="No matching students" description="Clear the search or change the session filter." className="m-5" /> : (
        <>
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
                {shownStudents.map((student) => (
                  <TableRow key={student.student_id}>
                    <TableCell className="sticky left-0 bg-card"><strong className="block font-mono text-xs">{student.roll_number}</strong><span className="mt-0.5 block text-xs text-muted-foreground">{student.display_name}</span></TableCell>
                    {sessions.map((item) => <RegisterMark key={item.id} status={student.statuses[item.id]} />)}
                    <TableCell className="text-center">{student.present}</TableCell>
                    <TableCell className="text-center">{student.absent}</TableCell>
                    <TableCell className="text-center"><StatusBadge tone={student.percentage >= 75 ? "success" : "warning"}>{student.percentage.toFixed(0)}%</StatusBadge></TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
          {matchingStudents.length > shownStudents.length ? <p className="border-t px-5 py-3 text-xs text-muted-foreground">Showing the first {shownStudents.length} matching students. The CSV export includes the complete filtered register.</p> : null}
        </>
      )}
    </Card>
  );
}

function RegisterMark({ status }: { status: string | null }) {
  return <TableCell className="text-center"><StatusBadge tone={status === "PRESENT" ? "success" : status === "ABSENT" ? "error" : "neutral"}>{status === "PRESENT" ? "P" : status === "ABSENT" ? "A" : "-"}</StatusBadge></TableCell>;
}

function BelowThresholdPanel() {
  const { register } = useFacultyPortal();
  const students = register ? register.students.filter((student) => student.present + student.absent > 0 && student.percentage < 75) : [];
  return (
    <Card>
      <SectionHeading title="Attendance risk" description="Students below the institutional 75% threshold for this course." action={<StatusBadge tone={students.length ? "warning" : "success"}>{students.length} students</StatusBadge>} />
      {students.length === 0 ? <EmptyPanel icon={Users} title="No students below threshold" description="Every student with recorded attendance currently meets the configured threshold." className="m-5" /> : (
        <div className="overflow-x-auto"><Table><TableHeader><TableRow><TableHead>Roll number</TableHead><TableHead>Student</TableHead><TableHead>Present</TableHead><TableHead>Absent</TableHead><TableHead className="text-right">Rate</TableHead></TableRow></TableHeader><TableBody>{students.slice(0, 10).map((student) => <TableRow key={student.student_id}><TableCell className="font-mono text-xs">{student.roll_number}</TableCell><TableCell className="font-medium">{student.display_name}</TableCell><TableCell>{student.present}</TableCell><TableCell>{student.absent}</TableCell><TableCell className="text-right"><StatusBadge tone="warning">{student.percentage.toFixed(0)}%</StatusBadge></TableCell></TableRow>)}</TableBody></Table></div>
      )}
    </Card>
  );
}

function SessionLedger() {
  const { sessionHistory } = useFacultyPortal();
  const records = sessionHistory.slice(0, 12);
  return (
    <Card>
      <SectionHeading title="Session ledger" description="Recent attendance sessions from courses assigned to this faculty account." />
      {records.length === 0 ? <EmptyPanel icon={CalendarRange} title="No sessions available" description="Completed sessions appear here after synchronization." className="m-5" /> : (
        <div className="overflow-x-auto"><Table><TableHeader><TableRow><TableHead>Date</TableHead><TableHead>Course</TableHead><TableHead>State</TableHead><TableHead className="text-right">Present</TableHead></TableRow></TableHeader><TableBody>{records.map((row) => <TableRow key={row.id}><TableCell>{dateLabel(new Date(row.scheduled_start))}</TableCell><TableCell className="font-medium">{row.course_code} · {row.section_code}</TableCell><TableCell><StatusBadge tone={row.state === "ACTIVE" ? "success" : "neutral"}>{titleCase(row.state)}</StatusBadge></TableCell><TableCell className="text-right">{row.present} / {row.expected}</TableCell></TableRow>)}</TableBody></Table></div>
      )}
    </Card>
  );
}
