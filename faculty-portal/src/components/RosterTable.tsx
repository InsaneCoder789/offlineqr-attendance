"use client";

import { Check, ClipboardList, UserCheck } from "lucide-react";
import { rosterStatus } from "@/lib/format";
import { useFacultyPortal } from "./FacultyPortalProvider";
import { Button } from "@/components/ui/button";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { EmptyPanel, StatusBadge } from "./PortalUI";

export function RosterTable() {
  const { roster, rosterFilter, rosterQuery, setConfirmStudent } = useFacultyPortal();
  const normalizedQuery = rosterQuery.trim().toLowerCase();
  const filtered = roster.filter((student) => {
    const isPresent = student.attendance_status === "PRESENT";
    const matchesFilter = rosterFilter === "all" || (rosterFilter === "present" && isPresent) || (rosterFilter === "pending" && !isPresent);
    const matchesQuery = !normalizedQuery || student.roll_number.toLowerCase().includes(normalizedQuery) || student.display_name.toLowerCase().includes(normalizedQuery);
    return matchesFilter && matchesQuery;
  });

  if (roster.length === 0) return <EmptyPanel icon={ClipboardList} title="Roster unavailable" description="The enrolled student roster will appear after the session synchronizes." className="m-5" />;
  if (filtered.length === 0) return <EmptyPanel icon={UserCheck} title="No matching students" description="Clear the search or change the roster filter." className="m-5" />;

  return (
    <div className="overflow-x-auto">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Roll number</TableHead>
            <TableHead>Student</TableHead>
            <TableHead>Attendance state</TableHead>
            <TableHead className="text-right">Faculty action</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {filtered.map((student) => {
            const isPresent = student.attendance_status === "PRESENT";
            const status = rosterStatus(student);
            return (
              <TableRow key={student.student_id}>
                <TableCell className="font-mono text-xs font-medium">{student.roll_number}</TableCell>
                <TableCell className="font-medium">{student.display_name}</TableCell>
                <TableCell><StatusBadge tone={status.tone === "error" ? "error" : status.tone}>{status.label}</StatusBadge></TableCell>
                <TableCell className="text-right">
                  <Button variant="outline" size="sm" disabled={isPresent} onClick={() => setConfirmStudent(student)}>
                    <Check data-icon="inline-start" />{isPresent ? "Recorded" : "Attest present"}
                  </Button>
                </TableCell>
              </TableRow>
            );
          })}
        </TableBody>
      </Table>
    </div>
  );
}
