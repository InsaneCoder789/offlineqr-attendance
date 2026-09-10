"use client";

import { useRouter } from "next/navigation";
import { ArrowLeft, Radio, Search, Users } from "lucide-react";
import { presentCount } from "@/lib/format";
import { useFacultyPortal } from "./FacultyPortalProvider";
import { QrPanel } from "./QrPanel";
import { RosterTable } from "./RosterTable";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { EmptyPanel, PageIntro, SectionHeading, StatusBadge } from "./PortalUI";

export function AttendancePage() {
  const router = useRouter();
  const { roster, rosterFilter, rosterQuery, session, setRosterFilter, setRosterQuery } = useFacultyPortal();

  if (!session) {
    return (
      <>
        <PageIntro eyebrow="Classroom operations" title="Live attendance" description="Open a scheduled class to begin a signed dynamic QR session." />
        <EmptyPanel
          icon={Radio}
          title="No active attendance session"
          description="Choose a class from your teaching schedule, then start attendance when the classroom is ready."
          action={<Button onClick={() => router.push("/classes")}><ArrowLeft data-icon="inline-start" />Open classes</Button>}
          className="min-h-[28rem]"
        />
      </>
    );
  }

  return (
    <>
      <PageIntro
        eyebrow="Classroom operations"
        title={`${session.course_code} · ${session.section_code}`}
        description={`${session.course_name} · ${session.room ?? "Room TBC"}. The QR and roster remain bound to this session.`}
        actions={<StatusBadge tone="success" icon={Radio}>{presentCount(roster)} of {roster.length} present</StatusBadge>}
      />
      <section className="grid min-w-0 gap-5 xl:grid-cols-[minmax(21rem,0.78fr)_minmax(0,1.55fr)]">
        <QrPanel />
        <Card className="min-w-0">
          <SectionHeading title="Student roster" description="Search enrolled students, review proof states, and record controlled attestations." action={<StatusBadge tone="neutral" icon={Users}>{roster.length} enrolled</StatusBadge>} />
          <div className="grid gap-3 border-b p-5 lg:grid-cols-[minmax(15rem,1fr)_auto] lg:items-center">
            <div className="relative">
              <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
              <Input type="search" value={rosterQuery} placeholder="Search roll number or student name" aria-label="Search roster" className="pl-9" onChange={(event) => setRosterQuery(event.target.value)} />
            </div>
            <ToggleGroup
              value={[rosterFilter]}
              onValueChange={(value) => { const next = value[0] as typeof rosterFilter | undefined; if (next) setRosterFilter(next); }}
              variant="outline"
              spacing={0}
              aria-label="Roster filter"
              className="w-full lg:w-auto"
            >
              <ToggleGroupItem value="all" className="flex-1 lg:flex-none">All</ToggleGroupItem>
              <ToggleGroupItem value="present" className="flex-1 lg:flex-none">Present</ToggleGroupItem>
              <ToggleGroupItem value="pending" className="flex-1 lg:flex-none">Not recorded</ToggleGroupItem>
            </ToggleGroup>
          </div>
          <RosterTable />
        </Card>
      </section>
    </>
  );
}
