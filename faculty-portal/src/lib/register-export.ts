import { csvCell } from "./csv";
import type { FacultyRegister } from "../api";

export function buildRegisterCsv(register: FacultyRegister, query: string, dateFilter: string): string {
  const normalizedQuery = query.trim().toLowerCase();
  const sessions = dateFilter === "all"
    ? register.sessions
    : register.sessions.filter((item) => item.id === dateFilter);
  const students = register.students.filter((student) =>
    !normalizedQuery ||
    student.roll_number.toLowerCase().includes(normalizedQuery) ||
    student.display_name.toLowerCase().includes(normalizedQuery)
  );
  const header = ["Roll Number", "Student", ...sessions.map((item) => item.label), "Present", "Absent", "Percentage"];
  const rows = students.map((student) => [
    student.roll_number,
    student.display_name,
    ...sessions.map((item) => student.statuses[item.id] ?? ""),
    String(student.present),
    String(student.absent),
    student.percentage.toFixed(2),
  ]);
  return [header, ...rows].map((row) => row.map(csvCell).join(",")).join("\n");
}

export function downloadRegisterCsv(register: FacultyRegister, query: string, dateFilter: string): void {
  const blob = new Blob([buildRegisterCsv(register, query, dateFilter)], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = `${register.course_code}_${register.section_code}_attendance_register.csv`;
  link.click();
  URL.revokeObjectURL(url);
}
