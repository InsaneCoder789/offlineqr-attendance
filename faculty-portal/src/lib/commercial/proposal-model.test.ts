import { describe, expect, it } from "vitest";
import { proposalPrice, proposalSchema } from "./proposal-model";

const valid = { institution: "Example Institute", contact: "billing@example.edu", plan: "core", students: 2000 };

describe("commercial proposal boundaries", () => {
  it("calculates licence prices on the server", () => {
    expect(proposalPrice(proposalSchema.parse(valid))).toEqual({ name: "Essential", rate: 49, subtotal: 98000 });
    expect(proposalPrice(proposalSchema.parse({ ...valid, plan: "institution" })).subtotal).toBe(158000);
  });
  it("does not invent an enterprise price", () => {
    expect(proposalPrice(proposalSchema.parse({ ...valid, plan: "enterprise" })).subtotal).toBeNull();
  });
  it("rejects client prices, payment references and additional fields", () => {
    for (const value of [{ subtotal: 1 }, { paymentId: "paid" }, { rate: 0 }]) {
      expect(proposalSchema.safeParse({ ...valid, ...value }).success).toBe(false);
    }
  });
  it("rejects invalid plans, counts and email addresses", () => {
    for (const value of [{ plan: "unknown" }, { students: 99 }, { students: 100001 }, { students: 100.5 }, { contact: "not-an-email" }]) {
      expect(proposalSchema.safeParse({ ...valid, ...value }).success).toBe(false);
    }
  });
  it("bounds text and rejects control characters", () => {
    for (const value of [{ institution: "x".repeat(101) }, { requirements: "x".repeat(241) }, { institution: "Test\u0000Institute" }]) {
      expect(proposalSchema.safeParse({ ...valid, ...value }).success).toBe(false);
    }
  });
});
