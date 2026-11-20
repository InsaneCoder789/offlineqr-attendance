import { describe, expect, it } from "vitest";
import { buildBelowThresholdCsv, buildRegisterCsv, isBelowThreshold, normalizeThreshold, studentsBelowThreshold } from "./register-export";
import type { FacultyRegister } from "../api";

const register = {
  course_code: "CS101",
  section_code: "A",
  sessions: [{ id: "s1", label: "01 Aug" }, { id: "s2", label: "02 Aug" }],
  students: [
    { roll_number: "1", display_name: "=Ann", statuses: { s1: "PRESENT" }, present: 1, absent: 1, percentage: 50 },
    { roll_number: "2", display_name: "Bob", statuses: { s2: "PRESENT" }, present: 1, absent: 1, percentage: 50 },
  ],
} as unknown as FacultyRegister;

describe("buildRegisterCsv", () => {
  it("filters by student and session and neutralises formulas", () => {
    const csv = buildRegisterCsv(register, "ann", "s1");
    expect(csv.split("\n")).toEqual([
      '"Roll Number","Student","01 Aug","Present","Absent","Percentage"',
      `"1","'=Ann","PRESENT","1","1","50.00"`,
    ]);
  });
});

const risk = {
  course_code: "CS101",
  section_code: "A",
  sessions: [{ id: "s1", label: "01 Aug" }, { id: "s2", label: "02 Aug" }],
  students: [
    { roll_number: "1", display_name: "Low", statuses: { s1: "PRESENT", s2: "ABSENT" }, present: 1, absent: 1, percentage: 50 },
    { roll_number: "2", display_name: "Edge", statuses: { s1: "PRESENT", s2: "PRESENT" }, present: 3, absent: 1, percentage: 75 },
    { roll_number: "3", display_name: "NoData", statuses: {}, present: 0, absent: 0, percentage: 0 },
    { roll_number: "4", display_name: "Zero", statuses: { s1: "ABSENT", s2: "ABSENT" }, present: 0, absent: 2, percentage: 0 },
  ],
} as unknown as FacultyRegister;

describe("threshold reports", () => {
  it("treats exactly the threshold as passing and ignores students with no records", () => {
    expect(risk.students.map((s) => isBelowThreshold(s, 75))).toEqual([true, false, false, true]);
    expect(studentsBelowThreshold(risk, 50).map((s) => s.roll_number)).toEqual(["4"]);
  });
  it("exports only below-threshold students across all sessions", () => {
    expect(buildBelowThresholdCsv(risk, 75).split("\n")).toEqual([
      '"Roll Number","Student","01 Aug","02 Aug","Present","Absent","Percentage"',
      '"1","Low","PRESENT","ABSENT","1","1","50.00"',
      '"4","Zero","ABSENT","ABSENT","0","2","0.00"',
    ]);
  });
  it("normalizes threshold input", () => {
    expect(normalizeThreshold(120)).toBe(100);
    expect(normalizeThreshold(-5)).toBe(0);
    expect(normalizeThreshold(Number.NaN)).toBe(75);
    expect(normalizeThreshold(80.456)).toBe(80.46);
  });
});
