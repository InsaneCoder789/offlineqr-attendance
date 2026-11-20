import { describe, expect, it } from "vitest";
import { classifyPortalError } from "./portal-errors";

const api = (status: number, message: string, code: string | null = null) => Object.assign(new Error(message), { status, code });

describe("classifyPortalError", () => {
  it("routes the password change code", () => {
    expect(classifyPortalError(api(403, "Change it", "FACULTY_PASSWORD_CHANGE_REQUIRED"), "x").kind).toBe("password_change_required");
  });
  it("detects expired sessions and keeps server text", () => {
    expect(classifyPortalError(api(401, "Session over", "FACULTY_SESSION_EXPIRED"), "x")).toEqual({ kind: "session_expired", message: "Session over" });
    expect(classifyPortalError(api(401, "nope"), "x").kind).toBe("session_expired");
  });
  it("keeps the rate limit message", () => {
    expect(classifyPortalError(api(429, "Slow down. Try again in 9 seconds.", "RATE_LIMITED"), "x")).toEqual({ kind: "rate_limited", message: "Slow down. Try again in 9 seconds." });
  });
  it("treats fetch failures as offline", () => {
    expect(classifyPortalError(new TypeError("Failed to fetch"), "x").kind).toBe("offline");
    expect(classifyPortalError(new Error("boom"), "x", false).kind).toBe("offline");
  });
  it("falls back to the generic message", () => {
    expect(classifyPortalError("weird", "Fallback")).toEqual({ kind: "generic", message: "Fallback" });
  });
});
