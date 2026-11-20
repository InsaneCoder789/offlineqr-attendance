import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ApiRequestError, startSession, cachedFacultyIdentity, cachedTodayClasses, cachedRoster, clearFacultyIdentity } from "./api";

describe("faculty cache boundaries", () => {
  let storage: Record<string, string>;
  beforeEach(() => {
    storage = {};
    const api = {
      getItem: (key: string) => storage[key] ?? null,
      setItem: (key: string, value: string) => { storage[key] = value; },
      removeItem: (key: string) => { delete storage[key]; },
    };
    vi.stubGlobal("localStorage", new Proxy(api, {
      ownKeys: () => Object.keys(storage),
      getOwnPropertyDescriptor: () => ({ enumerable: true, configurable: true }),
    }));
  });
  afterEach(() => vi.unstubAllGlobals());

  it("preserves a denied session start as an authorization error", async () => {
    vi.stubGlobal("document", { cookie: "" });
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(JSON.stringify({ error: { message: "Course access denied" } }), { status: 403 })));
    await expect(startSession("unassigned-course")).rejects.toMatchObject({ status: 403, message: "Course access denied" });
    await expect(startSession("unassigned-course")).rejects.toBeInstanceOf(ApiRequestError);
  });

  it("recovers from truncated JSON and invalid collection shapes", () => {
    storage["faculty.identity"] = "{";
    storage["faculty.todayClasses"] = "{}";
    storage["faculty.roster.session"] = "null";
    expect(cachedFacultyIdentity()).toBeNull();
    expect(cachedTodayClasses()).toEqual([]);
    expect(cachedRoster("session")).toEqual([]);
  });

  it("removes cached private data on logout without clearing other applications", () => {
    for (const key of ["faculty.identity", "faculty.register.course", "faculty.roster.session", "faculty.offlineSessions", "faculty.lastLogin"]) storage[key] = "private";
    storage["other.application"] = "keep";
    clearFacultyIdentity();
    expect(storage).toEqual({ "other.application": "keep" });
  });
});
