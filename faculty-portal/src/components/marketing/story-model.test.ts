import { describe, expect, it } from "vitest";
import { annualEstimate, chapterAt } from "./story-model";

describe("editorial model boundaries", () => {
  it("keeps all chapter indexes within the narrative", () => {
    expect([-1, 0, .25, .5, .75, 1, 2].map(chapterAt)).toEqual([0, 0, 1, 2, 3, 3, 3]);
  });
  it("calculates a bounded annual proposal", () => {
    expect(annualEstimate(49, 1000)).toBe(49000);
    expect(annualEstimate(79, 0)).toBe(7900);
    expect(annualEstimate(79, Infinity)).toBe(7900);
    expect(annualEstimate(49, 100001)).toBe(4900000);
  });
});
