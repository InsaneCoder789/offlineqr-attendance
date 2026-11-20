import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

const root = path.resolve(process.cwd(), "..");
const read = (name: string) => readFileSync(path.join(root, name), "utf8");
// scripts/bootstrap_demo.py is a local-only helper (excluded from Git), so its checks run only where it exists.
const demoBootstrap = existsSync(path.join(root, "scripts/bootstrap_demo.py")) ? read("scripts/bootstrap_demo.py") : "";

describe("public development data policy", () => {
  it("uses only sample email domains in the seed and demo bootstrap", () => {
    const samples = read("backend/seeds/goal02_dev_seed.sql") + demoBootstrap;
    const domains = [...samples.matchAll(/[A-Za-z0-9._%+-]+@([A-Za-z0-9.-]+\.[A-Za-z]{2,})/g)].map(match => match[1]);
    expect(domains.length).toBeGreaterThan(0);
    expect(domains.every(domain => domain === "example.edu")).toBe(true);
  });
  it("keeps the demo student aligned with the synthetic development seed", () => {
    expect(read("backend/seeds/goal02_dev_seed.sql")).toContain("'90010001'");
    if (demoBootstrap) {
      expect(demoBootstrap).toContain("'90010001'");
      expect(demoBootstrap).toContain("phone_number = NULL");
    }
  });
  it("excludes confidential records and generated commercial documents from Git", () => {
    const rules = read(".gitignore").split(/\r?\n/);
    for (const rule of ["*.xlsx", "*.xls", "*.csv", "*.db", "*.sqlite", "output/pdf/"]) {
      expect(rules).toContain(rule);
    }
  });
});
