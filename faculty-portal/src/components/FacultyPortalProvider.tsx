"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import {
  attest,
  cachedActiveSession,
  cachedFacultyCourses,
  cachedFacultyIdentity,
  cachedFacultyRegister,
  cachedSessionHistory,
  cachedTodayClasses,
  clearCachedActiveSession,
  clearFacultyIdentity,
  closeSession,
  fetchFacultyCourses,
  fetchFacultyProfile,
  fetchFacultyRegister,
  fetchRoster,
  fetchSession,
  fetchSessionHistory,
  fetchTodayClasses,
  facultySessionEventUrl,
  loginFaculty,
  logoutFaculty,
  startSession,
  changeFacultyPassword,
  updateFacultyProfile,
  type FacultyClass,
  type FacultyCourse,
  type FacultyIdentity,
  type FacultyRegister,
  type FacultySession,
  type FacultySessionRecord,
  type RosterStudent,
} from "../api";

type RosterFilter = "all" | "present" | "pending";

type FacultyPortalState = {
  classes: FacultyClass[];
  facultyCourses: FacultyCourse[];
  sessionHistory: FacultySessionRecord[];
  selectedRegisterOfferingId: string | null;
  register: FacultyRegister | null;
  session: FacultySession | null;
  roster: RosterStudent[];
  facultyIdentity: FacultyIdentity | null;
  loginEmail: string;
  loginPassword: string;
  loginLoading: boolean;
  loading: boolean;
  error: string | null;
  online: boolean;
  projectorMode: boolean;
  confirmStudent: RosterStudent | null;
  attestationReason: string;
  rosterQuery: string;
  rosterFilter: RosterFilter;
  registerQuery: string;
  registerDateFilter: string;
  setLoginEmail: (value: string) => void;
  setLoginPassword: (value: string) => void;
  setProjectorMode: (value: boolean) => void;
  setConfirmStudent: (value: RosterStudent | null) => void;
  setAttestationReason: (value: string) => void;
  setRosterQuery: (value: string) => void;
  setRosterFilter: (value: RosterFilter) => void;
  setRegisterQuery: (value: string) => void;
  setRegisterDateFilter: (value: string) => void;
  submitFacultyLogin: () => Promise<void>;
  switchFaculty: () => Promise<void>;
  updateProfile: (displayName: string, phoneNumber: string | null) => Promise<void>;
  changePassword: (currentPassword: string, newPassword: string) => Promise<void>;
  refresh: () => Promise<void>;
  refreshRegister: (courseOfferingId: string) => Promise<void>;
  start: (courseOfferingId: string) => Promise<boolean>;
  endSession: () => Promise<void>;
  confirmAttestation: () => Promise<void>;
  exportRegisterCsv: () => void;
};

const FacultyPortalContext = createContext<FacultyPortalState | null>(null);
const defaultFacultyEmail = "";
const defaultReason = "Student device failure";

export function FacultyPortalProvider({ children }: { children: React.ReactNode }) {
  const [classes, setClasses] = useState<FacultyClass[]>([]);
  const [facultyCourses, setFacultyCourses] = useState<FacultyCourse[]>([]);
  const [sessionHistory, setSessionHistory] = useState<FacultySessionRecord[]>([]);
  const [selectedRegisterOfferingId, setSelectedRegisterOfferingId] = useState<string | null>(null);
  const [register, setRegister] = useState<FacultyRegister | null>(null);
  const [session, setSession] = useState<FacultySession | null>(null);
  const [roster, setRoster] = useState<RosterStudent[]>([]);
  const [facultyIdentity, setFacultyIdentity] = useState<FacultyIdentity | null>(null);
  const [loginEmail, setLoginEmail] = useState(defaultFacultyEmail);
  const [loginPassword, setLoginPassword] = useState("");
  const [loginLoading, setLoginLoading] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [online, setOnline] = useState(true);
  const [projectorMode, setProjectorMode] = useState(false);
  const [confirmStudent, setConfirmStudent] = useState<RosterStudent | null>(null);
  const [attestationReason, setAttestationReason] = useState(defaultReason);
  const [rosterQuery, setRosterQuery] = useState("");
  const [rosterFilter, setRosterFilter] = useState<RosterFilter>("all");
  const [registerQuery, setRegisterQuery] = useState("");
  const [registerDateFilter, setRegisterDateFilter] = useState("all");

  const defaultRegisterOfferingId = useCallback((courseList = facultyCourses, classList = classes) => {
    return courseList.find((item) => item.section_code === "CS21")?.course_offering_id ??
      classList.find((item) => item.section_code === "CS21")?.course_offering_id ??
      courseList[0]?.course_offering_id ??
      null;
  }, [classes, facultyCourses]);

  const refreshRegister = useCallback(async (courseOfferingId: string) => {
    setSelectedRegisterOfferingId(courseOfferingId);
    setRegister(cachedFacultyRegister(courseOfferingId));
    setLoading(true);
    setError(null);
    try {
      setRegister(await fetchFacultyRegister(courseOfferingId));
    } catch (exception) {
      setError(exception instanceof Error ? exception.message : "Register unavailable");
    } finally {
      setLoading(false);
    }
  }, []);

  const refresh = useCallback(async () => {
    if (!cachedFacultyIdentity()) return;
    setLoading(true);
    setError(null);
    try {
      const [today, courses, history] = await Promise.all([
        fetchTodayClasses(),
        fetchFacultyCourses(),
        fetchSessionHistory(),
      ]);
      setClasses(today);
      setFacultyCourses(courses);
      setSessionHistory(history);

      const selected = selectedRegisterOfferingId ?? defaultRegisterOfferingId(courses, today);
      if (selected) {
        setSelectedRegisterOfferingId(selected);
        setRegister(await fetchFacultyRegister(selected));
      }

      const active = cachedActiveSession();
      if (active) {
        const updatedSession = await fetchSession(active.id);
        if (updatedSession) {
          setSession(updatedSession);
          setRoster(await fetchRoster(updatedSession.id));
        } else {
          setSession(null);
          setRoster([]);
          clearCachedActiveSession();
        }
      }
    } catch (exception) {
      setError(exception instanceof Error ? exception.message : "Unable to sync");
      setClasses(cachedTodayClasses());
      setFacultyCourses(cachedFacultyCourses());
      setSessionHistory(cachedSessionHistory());
    } finally {
      setLoading(false);
    }
  }, [defaultRegisterOfferingId, selectedRegisterOfferingId]);

  const submitFacultyLogin = useCallback(async () => {
    const email = loginEmail.trim().toLowerCase();
    if (!email || !loginPassword) {
      setError("Enter your KIIT faculty email and password");
      return;
    }
    setLoginLoading(true);
    setError(null);
    try {
      const identity = await loginFaculty(email, loginPassword);
      setFacultyIdentity(identity);
      localStorage.setItem("faculty.lastLogin", email);
      await refresh();
    } catch (exception) {
      setError(exception instanceof Error ? exception.message : "Faculty login failed");
    } finally {
      setLoginLoading(false);
    }
  }, [loginEmail, loginPassword, refresh]);

  const switchFaculty = useCallback(async () => {
    try {
      await logoutFaculty();
    } catch {
      clearFacultyIdentity();
    }
    clearFacultyIdentity();
    setFacultyIdentity(null);
    setClasses([]);
    setFacultyCourses([]);
    setSessionHistory([]);
    setSelectedRegisterOfferingId(null);
    setRegister(null);
    setSession(null);
    setRoster([]);
  }, []);

  const updateProfile = useCallback(async (displayName: string, phoneNumber: string | null) => {
    setLoading(true);
    setError(null);
    try {
      setFacultyIdentity(await updateFacultyProfile(displayName, phoneNumber));
    } catch (exception) {
      setError(exception instanceof Error ? exception.message : "Could not update profile");
      throw exception;
    } finally {
      setLoading(false);
    }
  }, []);

  const changePassword = useCallback(async (currentPassword: string, newPassword: string) => {
    setLoading(true);
    setError(null);
    try {
      await changeFacultyPassword(currentPassword, newPassword);
      clearFacultyIdentity();
      clearCachedActiveSession();
      setFacultyIdentity(null);
      setSession(null);
      setRoster([]);
    } catch (exception) {
      setError(exception instanceof Error ? exception.message : "Could not change password");
      throw exception;
    } finally {
      setLoading(false);
    }
  }, []);

  const refreshActiveSession = useCallback(async (sessionId: string | null) => {
    if (!sessionId || loading) return;
    try {
      const updatedSession = await fetchSession(sessionId);
      if (!updatedSession) {
        setSession(null);
        setRoster([]);
        clearCachedActiveSession();
        return;
      }
      setSession(updatedSession);
      setRoster(await fetchRoster(updatedSession.id));
    } catch {
      // Keep the active classroom view usable with the last local roster.
    }
  }, [loading]);

  const start = useCallback(async (courseOfferingId: string) => {
    setLoading(true);
    setError(null);
    try {
      const nextSession = await startSession(courseOfferingId);
      setSession(nextSession);
      setRoster(await fetchRoster(nextSession.id));
      return true;
    } catch (exception) {
      setError(exception instanceof Error ? exception.message : "Session unavailable");
      return false;
    } finally {
      setLoading(false);
    }
  }, []);

  const endSession = useCallback(async () => {
    if (!session) return;
    setLoading(true);
    setError(null);
    try {
      await closeSession(session.id);
      setSessionHistory(await fetchSessionHistory());
      setSession(null);
      setRoster([]);
      setProjectorMode(false);
    } catch (exception) {
      setError(exception instanceof Error ? exception.message : "Could not close attendance session");
    } finally {
      setLoading(false);
    }
  }, [session]);

  const confirmAttestation = useCallback(async () => {
    if (!session || !confirmStudent) return;
    setLoading(true);
    setError(null);
    try {
      await attest(session.id, confirmStudent.student_id, attestationReason);
      setRoster(await fetchRoster(session.id));
      setConfirmStudent(null);
      setAttestationReason(defaultReason);
    } catch (exception) {
      setError(exception instanceof Error ? exception.message : "Faculty attestation failed");
    } finally {
      setLoading(false);
    }
  }, [attestationReason, confirmStudent, session]);

  const exportRegisterCsv = useCallback(() => {
    if (!register) return;
    const normalizedQuery = registerQuery.trim().toLowerCase();
    const sessions = registerDateFilter === "all"
      ? register.sessions
      : register.sessions.filter((item) => item.id === registerDateFilter);
    const students = register.students.filter((student) =>
      !normalizedQuery ||
      student.roll_number.toLowerCase().includes(normalizedQuery) ||
      student.display_name.toLowerCase().includes(normalizedQuery)
    );
    const header = ["Roll Number", "Student", ...sessions.map((item) => item.label), "Present", "Absent", "Percentage"];
    const rows = students.map((student) => [
      student.roll_number,
      student.display_name,
      ...sessions.map((item) => student.statuses[item.id] ?? ""),
      String(student.present),
      String(student.absent),
      student.percentage.toFixed(2),
    ]);
    const csv = [header, ...rows]
      .map((row) => row.map((cell) => `"${cell.replaceAll("\"", "\"\"")}"`).join(","))
      .join("\n");
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = `${register.course_code}_${register.section_code}_attendance_register.csv`;
    link.click();
    URL.revokeObjectURL(url);
  }, [register, registerDateFilter, registerQuery]);

  useEffect(() => {
    setOnline(navigator.onLine);
    const setOnlineState = () => setOnline(navigator.onLine);
    window.addEventListener("online", setOnlineState);
    window.addEventListener("offline", setOnlineState);

    const savedFacultyLogin = localStorage.getItem("faculty.lastLogin");
    if (savedFacultyLogin && savedFacultyLogin !== "dr.sarbeswar.mohanty@kiit.ac.in") {
      setLoginEmail(savedFacultyLogin);
    }
    const identity = cachedFacultyIdentity();
    setFacultyIdentity(identity);
    setClasses(cachedTodayClasses());
    const courses = cachedFacultyCourses();
    setFacultyCourses(courses);
    setSessionHistory(cachedSessionHistory());
    const active = cachedActiveSession();
    setSession(active);
    const selected = defaultRegisterOfferingId(courses, cachedTodayClasses());
    setSelectedRegisterOfferingId(selected);
    setRegister(cachedFacultyRegister(selected));
    void (async () => {
      try {
        const verified = await fetchFacultyProfile();
        if (!verified) {
          clearFacultyIdentity();
          setFacultyIdentity(null);
          return;
        }
        setFacultyIdentity(verified);
        await refresh();
      } catch {
        // Offline faculty access may display only cached workspace data.
      }
    })();

    return () => {
      window.removeEventListener("online", setOnlineState);
      window.removeEventListener("offline", setOnlineState);
    };
  }, []);

  useEffect(() => {
    const sessionId = session && !session.closed_at ? session.id : null;
    if (!sessionId || !online || !facultyIdentity) return;
    let socket: WebSocket | null = null;
    let fallbackTimer: number | null = null;
    let reconnectTimer: number | null = null;
    let disposed = false;

    const beginFallback = () => {
      if (fallbackTimer === null) fallbackTimer = window.setInterval(() => void refreshActiveSession(sessionId), 5000);
    };
    const connect = () => {
      if (disposed) return;
      socket = new WebSocket(facultySessionEventUrl(sessionId));
      socket.onopen = () => {
        if (fallbackTimer !== null) { window.clearInterval(fallbackTimer); fallbackTimer = null; }
      };
      socket.onmessage = () => void refreshActiveSession(sessionId);
      socket.onerror = () => socket?.close();
      socket.onclose = () => {
        if (disposed) return;
        beginFallback();
        reconnectTimer = window.setTimeout(connect, 4000);
      };
    };
    connect();
    return () => {
      disposed = true;
      socket?.close();
      if (fallbackTimer !== null) window.clearInterval(fallbackTimer);
      if (reconnectTimer !== null) window.clearTimeout(reconnectTimer);
    };
  }, [facultyIdentity, facultySessionEventUrl, online, refreshActiveSession, session?.closed_at, session?.id]);

  const value = useMemo<FacultyPortalState>(() => ({
    classes,
    facultyCourses,
    sessionHistory,
    selectedRegisterOfferingId,
    register,
    session,
    roster,
    facultyIdentity,
    loginEmail,
    loginPassword,
    loginLoading,
    loading,
    error,
    online,
    projectorMode,
    confirmStudent,
    attestationReason,
    rosterQuery,
    rosterFilter,
    registerQuery,
    registerDateFilter,
    setLoginEmail,
    setLoginPassword,
    setProjectorMode,
    setConfirmStudent,
    setAttestationReason,
    setRosterQuery,
    setRosterFilter,
    setRegisterQuery,
    setRegisterDateFilter,
    submitFacultyLogin,
    switchFaculty,
    updateProfile,
    changePassword,
    refresh,
    refreshRegister,
    start,
    endSession,
    confirmAttestation,
    exportRegisterCsv,
  }), [
    attestationReason,
    classes,
    confirmAttestation,
    confirmStudent,
    endSession,
    error,
    exportRegisterCsv,
    facultyCourses,
    facultyIdentity,
    loading,
    loginEmail,
    loginLoading,
    loginPassword,
    online,
    projectorMode,
    refresh,
    refreshRegister,
    register,
    registerDateFilter,
    registerQuery,
    roster,
    rosterFilter,
    rosterQuery,
    selectedRegisterOfferingId,
    session,
    sessionHistory,
    start,
    submitFacultyLogin,
    switchFaculty,
    updateProfile,
    changePassword,
  ]);

  return (
    <FacultyPortalContext.Provider value={value}>
      {children}
    </FacultyPortalContext.Provider>
  );
}

export function useFacultyPortal() {
  const context = useContext(FacultyPortalContext);
  if (!context) throw new Error("useFacultyPortal must be used inside FacultyPortalProvider");
  return context;
}
