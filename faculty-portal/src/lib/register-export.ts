import { csvCell } from "./csv";
import type { FacultyRegister } from "../api";

type RegisterStudent = FacultyRegister["students"][number];

/** A student counts only once they have at least one recorded session. */
export function isBelowThreshold(student: RegisterStudent, thresholdPercent: number): boolean {
  return student.present + student.absent > 0 && student.percentage < thresholdPercent;
}

export function studentsBelowThreshold(register: FacultyRegister, thresholdPercent: number): RegisterStudent[] {
  return register.students.filter((student) => isBelowThreshold(student, thresholdPercent));
}

/** Clamps free-typed input to a usable 0-100 percentage; falls back to the default. */
export function normalizeThreshold(value: number, fallback = 75): number {
  if (!Number.isFinite(value)) return fallback;
  return Math.min(100, Math.max(0, Math.round(value * 100) / 100));
}

export function buildRegisterCsv(
  register: FacultyRegister,
  query: string,
  dateFilter: string,
  options: { belowPercent?: number } = {},
): string {
  const normalizedQuery = query.trim().toLowerCase();
  const sessions = dateFilter === "all"
    ? register.sessions
    : register.sessions.filter((item) => item.id === dateFilter);
  const students = register.students.filter((student) =>
    (options.belowPercent === undefined || isBelowThreshold(student, options.belowPercent)) &&
    (!normalizedQuery ||
      student.roll_number.toLowerCase().includes(normalizedQuery) ||
      student.display_name.toLowerCase().includes(normalizedQuery))
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

/** CSV of only the students under the threshold, across every session in the register. */
export function buildBelowThresholdCsv(register: FacultyRegister, thresholdPercent: number): string {
  return buildRegisterCsv(register, "", "all", { belowPercent: thresholdPercent });
}

function saveCsv(csv: string, filename: string): void {
  const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  link.click();
  URL.revokeObjectURL(url);
}

export function downloadRegisterCsv(register: FacultyRegister, query: string, dateFilter: string): void {
  saveCsv(buildRegisterCsv(register, query, dateFilter), `${register.course_code}_${register.section_code}_attendance_register.csv`);
}

export function downloadBelowThresholdCsv(register: FacultyRegister, thresholdPercent: number): void {
  saveCsv(
    buildBelowThresholdCsv(register, thresholdPercent),
    `${register.course_code}_${register.section_code}_below_${thresholdPercent}pct.csv`,
  );
}
