import { describe, expect, test } from "vitest";
import { challengeFor, epochFor, secondsUntilNextEpoch } from "./protocol";

describe("attendance QR protocol", () => {
  test("calculates five-second epochs", () => {
    const origin = new Date("2026-08-18T10:00:00.000Z");
    expect(epochFor(new Date("2026-08-18T10:00:04.900Z"), origin)).toBe(0);
    expect(epochFor(new Date("2026-08-18T10:00:05.000Z"), origin)).toBe(1);
    expect(epochFor(new Date("2026-08-18T10:00:10.000Z"), origin)).toBe(2);
  });

  test("reports countdown from protocol time", () => {
    const origin = new Date("2026-08-18T10:00:00.000Z");
    expect(secondsUntilNextEpoch(new Date("2026-08-18T10:00:02.000Z"), origin)).toBe(3);
  });

  test("challenge is deterministic for session and epoch", () => {
    expect(challengeFor("session-1", 4, "public")).toBe(challengeFor("session-1", 4, "public"));
    expect(challengeFor("session-1", 4, "public")).not.toBe(challengeFor("session-1", 5, "public"));
  });
});
