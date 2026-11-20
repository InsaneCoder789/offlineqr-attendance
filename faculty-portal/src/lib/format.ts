import type { FacultyClass, FacultyIdentity, FacultySession, RosterStudent } from "../api";

export function presentCount(roster: RosterStudent[]): number {
  return roster.filter((student) => student.attendance_status === "PRESENT").length;
}

export function rosterStatus(student: RosterStudent): { label: string; tone: "success" | "warning" | "neutral" | "error" } {
  if (student.attendance_status === "PRESENT") {
    return {
      label: student.attendance_method === "FACULTY_ATTESTATION" ? "Faculty attested" : "Server verified",
      tone: "success",
    };
  }
  if (student.claim_state === "CONSUMED") return { label: "Verified proof", tone: "success" };
  if (student.claim_state === "PROOF_READY") return { label: "Sync pending", tone: "warning" };
  if (student.claim_state === "AWAITING_PRESENCE") return { label: "Claim captured", tone: "warning" };
  return { label: "Not recorded", tone: "neutral" };
}

export function minutes(value: string): number {
  const [hour, minute] = value.split(":").map(Number);
  return hour * 60 + minute;
}

export function dayPart(): string {
  const hour = new Date().getHours();
  if (hour < 12) return "morning";
  if (hour < 17) return "afternoon";
  return "evening";
}

export function isSameDay(first: Date, second: Date): boolean {
  return first.getFullYear() === second.getFullYear() &&
    first.getMonth() === second.getMonth() &&
    first.getDate() === second.getDate();
}

export function stateLabel(item: FacultyClass, session: FacultySession | null): string {
  if (session?.course_offering_id === item.course_offering_id && !session.closed_at) return "Attendance Active";
  const current = new Date().getHours() * 60 + new Date().getMinutes();
  if (current > minutes(item.end_time)) return "Completed";
  if (current >= minutes(item.start_time) && current <= minutes(item.end_time)) return "Now";
  return item.offline_ready ? "Ready" : "Scheduled";
}

export function stateClass(item: FacultyClass, session: FacultySession | null): string {
  if (session?.course_offering_id === item.course_offering_id && !session.closed_at) return "success";
  const current = new Date().getHours() * 60 + new Date().getMinutes();
  if (current > minutes(item.end_time)) return "neutral";
  if (current >= minutes(item.start_time) && current <= minutes(item.end_time)) return "success";
  return item.offline_ready ? "neutral" : "warning";
}

export function formatTime(value: string): string {
  return value.slice(0, 5);
}

export function dateLabel(date: Date): string {
  return new Intl.DateTimeFormat("en-IN", {
    weekday: "long",
    day: "numeric",
    month: "long",
  }).format(date);
}

export function titleCase(value: string): string {
  return value.toLowerCase().replace(/\b\w/g, (match) => match.toUpperCase());
}

export function facultyInitials(faculty: FacultyIdentity | null): string {
  const name = faculty?.display_name.trim();
  if (!name) return "FC";
  return name
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() ?? "")
    .join("") || "FC";
}

export function titleFor(pathname: string): string {
  if (pathname.startsWith("/classes")) return "My Classes";
  if (pathname.startsWith("/attendance")) return "Live Attendance";
  if (pathname.startsWith("/records")) return "Attendance Records";
  if (pathname.startsWith("/settings")) return "Settings";
  return "Preview";
}
