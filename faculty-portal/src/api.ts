import type { SessionAuthorization } from "./protocol";

export const ATTENDANCE_API_BASE = process.env.NEXT_PUBLIC_ATTENDANCE_API_BASE ?? "http://127.0.0.1:8000";

export class ApiRequestError extends Error {
  constructor(public readonly status: number, message: string, public readonly code: string | null = null) {
    super(message);
    this.name = "ApiRequestError";
  }
}

export type FacultyClass = {
  course_offering_id: string;
  course_code: string;
  course_name: string;
  section_code: string;
  room: string;
  start_time: string;
  end_time: string;
  offline_ready: boolean;
};

export type FacultyIdentity = {
  id: string;
  employee_code: string | null;
  institutional_email: string;
  display_name: string;
  phone_number: string | null;
  designation: string | null;
  org_unit: string | null;
  access_role?: "FACULTY" | "ICT_ADMIN";
  must_change_password: boolean;
  password_changed_at: string | null;
  last_login_at: string | null;
};

export type FacultySession = {
  id: string;
  course_offering_id: string;
  course_code: string;
  course_name: string;
  section_code: string;
  room: string | null;
  scheduled_start: string;
  scheduled_end: string;
  started_at: string;
  closed_at: string | null;
  state: string;
  authorization: SessionAuthorization;
  offline_pending_activation?: boolean;
};

type PendingSessionClose = {
  sessionId: string;
  courseOfferingId: string;
};

export type RosterStudent = {
  student_id: string;
  roll_number: string;
  display_name: string;
  attendance_status: string | null;
  attendance_method: string | null;
  claim_state: string | null;
};

export type FacultyCourse = {
  course_offering_id: string;
  course_code: string;
  course_name: string;
  section_code: string;
  student_count: number;
  schedule_summary: string;
};

export type FacultySessionRecord = {
  id: string;
  course_offering_id: string;
  course_code: string;
  course_name: string;
  section_code: string;
  room: string | null;
  scheduled_start: string;
  scheduled_end: string;
  state: string;
  present: number;
  absent: number;
  expected: number;
};

export type FacultyRegister = {
  course_offering_id: string;
  course_code: string;
  course_name: string;
  section_code: string;
  sessions: Array<{
    id: string;
    label: string;
    scheduled_start: string;
    state: string;
  }>;
  students: Array<{
    student_id: string;
    roll_number: string;
    display_name: string;
    present: number;
    absent: number;
    percentage: number;
    statuses: Record<string, string | null>;
  }>;
};

export function cachedFacultyIdentity(): FacultyIdentity | null {
  return readCache<FacultyIdentity | null>("faculty.identity", null);
}

function readCache<T>(key: string, fallback: T): T {
  try {
    const raw = localStorage.getItem(key);
    if (!raw) return fallback;
    const parsed = JSON.parse(raw) as T;
    if (Array.isArray(fallback) && !Array.isArray(parsed)) return fallback;
    return parsed;
  } catch {
    try { localStorage.removeItem(key); } catch { /* Storage can be disabled. */ }
    return fallback;
  }
}

// The active session carries the QR signing key, so it lives in per-tab sessionStorage
// (cleared when the tab closes) instead of the long-lived localStorage cache.
const ACTIVE_SESSION_KEY = "faculty.activeSession";

function saveActiveSession(value: string): void {
  try { sessionStorage.setItem(ACTIVE_SESSION_KEY, value); } catch { /* Storage can be disabled. */ }
  try { localStorage.removeItem(ACTIVE_SESSION_KEY); } catch { /* Storage can be disabled. */ }
}

function clearActiveSession(): void {
  try { sessionStorage.removeItem(ACTIVE_SESSION_KEY); } catch { /* Storage can be disabled. */ }
  try { localStorage.removeItem(ACTIVE_SESSION_KEY); } catch { /* Storage can be disabled. */ }
}

function readActiveSession(): FacultySession | null {
  try {
    const raw = sessionStorage.getItem(ACTIVE_SESSION_KEY);
    return raw ? (JSON.parse(raw) as FacultySession) : null;
  } catch {
    return null;
  }
}

export function saveFacultyIdentity(identity: FacultyIdentity): void {
  localStorage.setItem("faculty.identity", JSON.stringify(identity));
}

export function clearFacultyIdentity(): void {
  for (const key of Object.keys(localStorage)) {
    if (key.startsWith("faculty.")) localStorage.removeItem(key);
  }
  clearActiveSession();
}

export async function throwApiError(response: Response, fallback: string): Promise<never> {
  const body = await response.json().catch(() => null);
  const code: string | null = body?.error?.code ?? null;
  let message: string = body?.error?.message ?? fallback;
  if (response.status === 429) {
    const wait = Number(response.headers.get("Retry-After"));
    if (Number.isFinite(wait) && wait > 0) message = `${message} Try again in ${wait} seconds.`;
  }
  throw new ApiRequestError(response.status, message, code ?? (response.status === 429 ? "RATE_LIMITED" : null));
}

function csrfToken(): string {
  const token = document.cookie
    .split("; ")
    .find((item) => item.startsWith("offlineqr_faculty_csrf="))
    ?.split("=")[1];
  return token ? decodeURIComponent(token) : "";
}

function apiHeaders(mutating = false, contentType = false): HeadersInit {
  const headers: Record<string, string> = {};
  if (contentType) headers["Content-Type"] = "application/json";
  if (mutating) {
    const csrf = csrfToken();
    if (csrf) headers["X-CSRF-Token"] = csrf;
  }
  return headers;
}

async function apiFetch(path: string, init: RequestInit = {}): Promise<Response> {
  return fetch(`${ATTENDANCE_API_BASE}${path}`, {
    ...init,
    credentials: "include",
    cache: "no-store",
    headers: { ...apiHeaders(Boolean(init.method && init.method !== "GET" && init.method !== "HEAD"), Boolean(init.body)), ...init.headers },
  });
}

export function facultySessionEventUrl(sessionId: string): string {
  const endpoint = new URL(ATTENDANCE_API_BASE);
  endpoint.protocol = endpoint.protocol === "https:" ? "wss:" : "ws:";
  endpoint.pathname = `/api/v1/faculty/attendance-sessions/${sessionId}/events`;
  endpoint.search = "";
  return endpoint.toString();
}

export async function loginFaculty(email: string, password: string): Promise<FacultyIdentity> {
  const response = await apiFetch("/api/v1/faculty/auth/login", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  });
  if (response.status === 429) {
    const wait = Number(response.headers.get("Retry-After"));
    throw new ApiRequestError(429, Number.isFinite(wait) && wait > 0
      ? `Too many sign-in attempts. Try again in ${wait} seconds.`
      : "Too many sign-in attempts. Try again shortly.");
  }
  if (response.status >= 500) throw new ApiRequestError(response.status, "The attendance service is unavailable. Try again shortly.");
  if (!response.ok) await throwApiError(response, "Unable to sign in with those credentials");
  const profile = (await response.json()) as FacultyIdentity;
  saveFacultyIdentity(profile);
  return profile;
}

export async function logoutFaculty(): Promise<void> {
  await apiFetch("/api/v1/faculty/auth/logout", { method: "POST" });
  clearFacultyIdentity();
}

export async function fetchFacultyProfile(): Promise<FacultyIdentity | null> {
  const response = await apiFetch("/api/v1/faculty/profile");
  if (response.status === 401) return null;
  if (!response.ok) await throwApiError(response, "Could not restore the faculty session");
  const profile = (await response.json()) as FacultyIdentity;
  saveFacultyIdentity(profile);
  return profile;
}

export async function updateFacultyProfile(displayName: string, phoneNumber: string | null): Promise<FacultyIdentity> {
  const response = await apiFetch("/api/v1/faculty/profile", {
    method: "PATCH",
    body: JSON.stringify({ display_name: displayName, phone_number: phoneNumber }),
  });
  if (!response.ok) await throwApiError(response, "Could not update the faculty profile");
  const profile = (await response.json()) as FacultyIdentity;
  saveFacultyIdentity(profile);
  return profile;
}

export async function changeFacultyPassword(currentPassword: string, newPassword: string): Promise<void> {
  const response = await apiFetch("/api/v1/faculty/auth/password", {
    method: "POST",
    body: JSON.stringify({ current_password: currentPassword, new_password: newPassword }),
  });
  if (!response.ok) await throwApiError(response, "Could not change the password");
}

export async function fetchTodayClasses(): Promise<FacultyClass[]> {
  const response = await apiFetch("/api/v1/faculty/classes/today");
  if (!response.ok) await throwApiError(response, "Could not load today's classes");
  const classes = (await response.json()) as FacultyClass[];
  localStorage.setItem("faculty.todayClasses", JSON.stringify(classes));
  return classes;
}

export function cachedTodayClasses(): FacultyClass[] {
  return readCache<FacultyClass[]>("faculty.todayClasses", []);
}

export async function fetchFacultyCourses(): Promise<FacultyCourse[]> {
  const response = await apiFetch("/api/v1/faculty/courses");
  if (!response.ok) await throwApiError(response, "Could not load assigned courses");
  const courses = (await response.json()) as FacultyCourse[];
  localStorage.setItem("faculty.courses", JSON.stringify(courses));
  return courses;
}

export function cachedFacultyCourses(): FacultyCourse[] {
  return readCache<FacultyCourse[]>("faculty.courses", []);
}

export async function fetchSessionHistory(): Promise<FacultySessionRecord[]> {
  const response = await apiFetch("/api/v1/faculty/attendance-sessions?limit=50");
  if (!response.ok) await throwApiError(response, "Could not load attendance records");
  const records = (await response.json()) as FacultySessionRecord[];
  localStorage.setItem("faculty.sessionHistory", JSON.stringify(records));
  return records;
}

export function cachedSessionHistory(): FacultySessionRecord[] {
  return readCache<FacultySessionRecord[]>("faculty.sessionHistory", []);
}

export async function fetchFacultyRegister(courseOfferingId: string): Promise<FacultyRegister> {
  const response = await apiFetch(`/api/v1/faculty/course-offerings/${courseOfferingId}/register`);
  if (!response.ok) await throwApiError(response, "Could not load attendance register");
  const register = (await response.json()) as FacultyRegister;
  localStorage.setItem(`faculty.register.${courseOfferingId}`, JSON.stringify(register));
  return register;
}

export function cachedFacultyRegister(courseOfferingId: string | null): FacultyRegister | null {
  if (!courseOfferingId) return null;
  return readCache<FacultyRegister | null>(`faculty.register.${courseOfferingId}`, null);
}

export async function startSession(courseOfferingId: string): Promise<FacultySession> {
  const response = await apiFetch("/api/v1/faculty/attendance-sessions/start", {
    method: "POST",
    body: JSON.stringify({ course_offering_id: courseOfferingId }),
  });
  if (!response.ok) {
    await throwApiError(response, "Attendance session could not be started.");
  }
  const session = (await response.json()) as FacultySession;
  saveActiveSession(JSON.stringify(session));
  return session;
}

export async function prepareOfflineSessions(): Promise<FacultySession[]> {
  const response = await apiFetch("/api/v1/faculty/attendance-sessions/offline-package", {
    method: "POST",
  });
  if (!response.ok) await throwApiError(response, "Could not prepare offline attendance sessions");
  const sessions = (await response.json()) as FacultySession[];
  localStorage.setItem("faculty.offlineSessions", JSON.stringify(sessions));
  return sessions;
}

export function cachedOfflineSessions(): FacultySession[] {
  return readCache<FacultySession[]>("faculty.offlineSessions", []);
}

export function startCachedOfflineSession(courseOfferingId: string): FacultySession {
  const prepared = cachedOfflineSessions().find(
    (item) => item.course_offering_id === courseOfferingId && new Date(item.authorization.valid_until) > new Date(),
  );
  if (!prepared?.authorization.session_private_key) {
    throw new Error("This class was not prepared for offline attendance. Connect once before class to refresh it.");
  }
  const session: FacultySession = {
    ...prepared,
    state: "ACTIVE",
    offline_pending_activation: true,
  };
  saveActiveSession(JSON.stringify(session));
  return session;
}

export function queueOfflineSessionClose(session: FacultySession): void {
  const pending = pendingSessionCloses().filter((item) => item.sessionId !== session.id);
  pending.push({ sessionId: session.id, courseOfferingId: session.course_offering_id });
  localStorage.setItem("faculty.pendingSessionCloses", JSON.stringify(pending));
  clearActiveSession();
}

export function pendingSessionCloses(): PendingSessionClose[] {
  return readCache<PendingSessionClose[]>("faculty.pendingSessionCloses", []);
}

export async function reconcileOfflineSessions(): Promise<FacultySession | null> {
  let active = cachedActiveSession();
  if (active?.offline_pending_activation) {
    active = await startSession(active.course_offering_id);
  }
  const pending = pendingSessionCloses();
  const remaining: PendingSessionClose[] = [];
  for (const item of pending) {
    try {
      const activated = await startSession(item.courseOfferingId);
      await closeSession(activated.id);
    } catch {
      remaining.push(item);
    }
  }
  localStorage.setItem("faculty.pendingSessionCloses", JSON.stringify(remaining));
  return active;
}

export function cachedActiveSession(): FacultySession | null {
  return readActiveSession();
}

export function clearCachedActiveSession(): void {
  clearActiveSession();
}

export async function fetchSession(sessionId: string): Promise<FacultySession | null> {
  const response = await apiFetch(`/api/v1/faculty/attendance-sessions/${sessionId}`);
  if (response.status === 404 || response.status === 403) return null;
  if (!response.ok) await throwApiError(response, "Could not verify active session");
  const verified = (await response.json()) as FacultySession;
  saveActiveSession(JSON.stringify(verified));
  return verified;
}

export async function closeSession(sessionId: string): Promise<void> {
  const response = await apiFetch(`/api/v1/faculty/attendance-sessions/${sessionId}/close`, {
    method: "POST",
  });
  if (!response.ok) await throwApiError(response, "Could not close attendance session");
  clearActiveSession();
}

export async function fetchRoster(sessionId: string): Promise<RosterStudent[]> {
  const response = await apiFetch(`/api/v1/faculty/attendance-sessions/${sessionId}/roster`);
  if (!response.ok) {
    await throwApiError(response, `Roster request failed with ${response.status}`);
  }
  const roster = (await response.json()) as RosterStudent[];
  localStorage.setItem(`faculty.roster.${sessionId}`, JSON.stringify(roster));
  return roster;
}

export function cachedRoster(sessionId: string): RosterStudent[] {
  return readCache<RosterStudent[]>(`faculty.roster.${sessionId}`, []);
}

export async function attest(sessionId: string, studentId: string, reason: string): Promise<void> {
  const response = await apiFetch(`/api/v1/faculty/attendance-sessions/${sessionId}/attest`, {
    method: "POST",
    body: JSON.stringify({ student_id: studentId, reason }),
  });
  if (!response.ok) await throwApiError(response, "Could not attest attendance");
}
