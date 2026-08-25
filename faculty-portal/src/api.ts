import type { SessionAuthorization } from "./protocol";

const API_BASE = "http://127.0.0.1:8000";

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
  const raw = localStorage.getItem("faculty.identity");
  return raw ? (JSON.parse(raw) as FacultyIdentity) : null;
}

export function saveFacultyIdentity(identity: FacultyIdentity): void {
  localStorage.setItem("faculty.identity", JSON.stringify(identity));
}

export function clearFacultyIdentity(): void {
  localStorage.removeItem("faculty.identity");
  localStorage.removeItem("faculty.activeSession");
}

export async function loginFaculty(email: string, password: string): Promise<FacultyIdentity> {
  const response = await fetch(`${API_BASE}/api/v1/faculty/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  });
  if (!response.ok) throw new Error("Faculty login failed");
  const profile = (await response.json()) as FacultyIdentity;
  saveFacultyIdentity(profile);
  return profile;
}

function facultyHeaders(): HeadersInit {
  const faculty = cachedFacultyIdentity();
  return faculty ? { "X-Faculty-Id": faculty.id } : {};
}

export async function fetchTodayClasses(): Promise<FacultyClass[]> {
  const response = await fetch(`${API_BASE}/api/v1/faculty/classes/today`, {
    headers: facultyHeaders(),
  });
  if (!response.ok) throw new Error("Could not load today's classes");
  const classes = (await response.json()) as FacultyClass[];
  localStorage.setItem("faculty.todayClasses", JSON.stringify(classes));
  return classes;
}

export function cachedTodayClasses(): FacultyClass[] {
  return JSON.parse(localStorage.getItem("faculty.todayClasses") ?? "[]") as FacultyClass[];
}

export async function fetchFacultyCourses(): Promise<FacultyCourse[]> {
  const response = await fetch(`${API_BASE}/api/v1/faculty/courses`, {
    headers: facultyHeaders(),
  });
  if (!response.ok) throw new Error("Could not load assigned courses");
  const courses = (await response.json()) as FacultyCourse[];
  localStorage.setItem("faculty.courses", JSON.stringify(courses));
  return courses;
}

export function cachedFacultyCourses(): FacultyCourse[] {
  return JSON.parse(localStorage.getItem("faculty.courses") ?? "[]") as FacultyCourse[];
}

export async function fetchSessionHistory(): Promise<FacultySessionRecord[]> {
  const response = await fetch(`${API_BASE}/api/v1/faculty/attendance-sessions?limit=50`, {
    headers: facultyHeaders(),
  });
  if (!response.ok) throw new Error("Could not load attendance records");
  const records = (await response.json()) as FacultySessionRecord[];
  localStorage.setItem("faculty.sessionHistory", JSON.stringify(records));
  return records;
}

export function cachedSessionHistory(): FacultySessionRecord[] {
  return JSON.parse(localStorage.getItem("faculty.sessionHistory") ?? "[]") as FacultySessionRecord[];
}

export async function fetchFacultyRegister(courseOfferingId: string): Promise<FacultyRegister> {
  const response = await fetch(`${API_BASE}/api/v1/faculty/course-offerings/${courseOfferingId}/register`, {
    headers: facultyHeaders(),
  });
  if (!response.ok) throw new Error("Could not load attendance register");
  const register = (await response.json()) as FacultyRegister;
  localStorage.setItem(`faculty.register.${courseOfferingId}`, JSON.stringify(register));
  return register;
}

export function cachedFacultyRegister(courseOfferingId: string | null): FacultyRegister | null {
  if (!courseOfferingId) return null;
  const raw = localStorage.getItem(`faculty.register.${courseOfferingId}`);
  return raw ? (JSON.parse(raw) as FacultyRegister) : null;
}

export async function startSession(courseOfferingId: string): Promise<FacultySession> {
  const response = await fetch(`${API_BASE}/api/v1/faculty/attendance-sessions/start`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...facultyHeaders() },
    body: JSON.stringify({ course_offering_id: courseOfferingId }),
  });
  if (!response.ok) throw new Error(await response.text());
  const session = (await response.json()) as FacultySession;
  localStorage.setItem("faculty.activeSession", JSON.stringify(session));
  return session;
}

export function cachedActiveSession(): FacultySession | null {
  const raw = localStorage.getItem("faculty.activeSession");
  return raw ? (JSON.parse(raw) as FacultySession) : null;
}

export function clearCachedActiveSession(): void {
  localStorage.removeItem("faculty.activeSession");
}

export async function fetchSession(sessionId: string): Promise<FacultySession | null> {
  const response = await fetch(`${API_BASE}/api/v1/faculty/attendance-sessions/${sessionId}`, {
    headers: facultyHeaders(),
  });
  if (response.status === 404 || response.status === 403) return null;
  if (!response.ok) throw new Error("Could not verify active session");
  const verified = (await response.json()) as FacultySession;
  localStorage.setItem("faculty.activeSession", JSON.stringify(verified));
  return verified;
}

export async function closeSession(sessionId: string): Promise<void> {
  const response = await fetch(`${API_BASE}/api/v1/faculty/attendance-sessions/${sessionId}/close`, {
    method: "POST",
    headers: facultyHeaders(),
  });
  if (!response.ok) throw new Error("Could not close attendance session");
  localStorage.removeItem("faculty.activeSession");
}

export async function fetchRoster(sessionId: string): Promise<RosterStudent[]> {
  const response = await fetch(`${API_BASE}/api/v1/faculty/attendance-sessions/${sessionId}/roster`, {
    headers: facultyHeaders(),
  });
  if (!response.ok) return [];
  return (await response.json()) as RosterStudent[];
}

export async function attest(sessionId: string, studentId: string, reason: string): Promise<void> {
  await fetch(`${API_BASE}/api/v1/faculty/attendance-sessions/${sessionId}/attest`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...facultyHeaders() },
    body: JSON.stringify({ student_id: studentId, reason }),
  });
}
