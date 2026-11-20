"use client";

import { Check, ClipboardList, UserCheck } from "lucide-react";
import { rosterStatus } from "@/lib/format";
import { usePortalData } from "./FacultyPortalProvider";
import { usePortalUiActions, useRosterFilters } from "./PortalUiState";
import { Button } from "@/components/ui/button";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { EmptyPanel, LoadingPanel, StatusBadge, useMinWidth } from "./PortalUI";

export function RosterTable() {
  const { roster, clearError, loading } = usePortalData();
  const wide = useMinWidth(768);
  const { rosterFilter, rosterQuery } = useRosterFilters();
  const { setConfirmStudent } = usePortalUiActions();
  const normalizedQuery = rosterQuery.trim().toLowerCase();
  const filtered = roster.filter((student) => {
    const isPresent = student.attendance_status === "PRESENT";
    const matchesFilter = rosterFilter === "all" || (rosterFilter === "present" && isPresent) || (rosterFilter === "pending" && !isPresent);
    const matchesQuery = !normalizedQuery || student.roll_number.toLowerCase().includes(normalizedQuery) || student.display_name.toLowerCase().includes(normalizedQuery);
    return matchesFilter && matchesQuery;
  });

  if (roster.length === 0 && loading) return <LoadingPanel rows={5} label="Loading roster" />;
  if (roster.length === 0) return <EmptyPanel icon={ClipboardList} title="Roster unavailable" description="The enrolled student roster will appear after the session synchronizes." className="m-5" />;
  if (filtered.length === 0) return <EmptyPanel icon={UserCheck} title="No matching students" description="Clear the search or change the roster filter." className="m-5" />;

  const presentTotal = roster.filter((student) => student.attendance_status === "PRESENT").length;

  return (
    <div className="overflow-x-auto" role="region" aria-label="Student roster" tabIndex={0}>
      <p role="status" aria-live="polite" aria-atomic="true" className="sr-only">
        Showing {filtered.length} of {roster.length} students. {presentTotal} marked present.
      </p>
      {!wide ? (
        <ul className="grid gap-2 p-3">
          {filtered.map((student) => {
            const isPresent = student.attendance_status === "PRESENT";
            const status = rosterStatus(student);
            return (
              <li key={student.student_id} className="flex min-w-0 flex-col gap-3 rounded-lg border bg-card p-3 [contain-intrinsic-size:auto_7.5rem] [content-visibility:auto]">
                <div className="flex min-w-0 items-start justify-between gap-2">
                  <div className="min-w-0"><strong className="block break-words text-sm font-medium">{student.display_name}</strong><span className="font-mono text-xs text-muted-foreground">{student.roll_number}</span></div>
                  <StatusBadge tone={status.tone === "error" ? "error" : status.tone}>{status.label}</StatusBadge>
                </div>
                <Button variant="outline" className="w-full" disabled={isPresent} aria-label={isPresent ? `${student.display_name}, roll ${student.roll_number}: attendance recorded` : `Attest ${student.display_name}, roll ${student.roll_number}, as present`} onClick={() => { clearError(); setConfirmStudent(student); }}>
                  <Check data-icon="inline-start" />{isPresent ? "Recorded" : "Attest present"}
                </Button>
              </li>
            );
          })}
        </ul>
      ) : (
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead scope="col">Roll number</TableHead>
            <TableHead scope="col">Student</TableHead>
            <TableHead scope="col">Attendance state</TableHead>
            <TableHead scope="col" className="text-right">Faculty action</TableHead>
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
                  <Button variant="outline" size="sm" disabled={isPresent} aria-label={isPresent ? `${student.display_name}, roll ${student.roll_number}: attendance recorded` : `Attest ${student.display_name}, roll ${student.roll_number}, as present`} onClick={() => { clearError(); setConfirmStudent(student); }}>
                    <Check data-icon="inline-start" />{isPresent ? "Recorded" : "Attest present"}
                  </Button>
                </TableCell>
              </TableRow>
            );
          })}
        </TableBody>
      </Table>
      )}
    </div>
  );
}
