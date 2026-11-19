import { describe, expect, it } from "vitest";
import { buildRegisterCsv } from "./register-export";
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
