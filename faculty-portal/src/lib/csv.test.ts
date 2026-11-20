import { expect, it } from "vitest";
import { csvCell } from "./csv";

it("keeps untrusted register cells literal in spreadsheet exports", () => {
  expect(csvCell('=HYPERLINK("https://example.org")')).toBe('"\'=HYPERLINK(""https://example.org"")"');
  expect(csvCell("  +1+2")).toBe('"\'  +1+2"');
  expect(csvCell('Student "A"')).toBe('"Student ""A"""');
});
