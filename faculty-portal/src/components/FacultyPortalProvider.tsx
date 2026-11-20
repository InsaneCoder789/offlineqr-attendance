"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";
import { downloadRegisterCsv } from "../lib/register-export";
import { useSessionEvents } from "../hooks/useSessionEvents";
import { ApiRequestError } from "../api";
import { classifyPortalError, type PortalError, type PortalErrorKind } from "../lib/portal-errors";
import {
  PortalUiProvider,
  defaultAttestationReason,
  useAttestationUi,
  useLoginFields,
  usePortalUiActions,
  useProjectorUi,
  useRegisterFilters,
  useRosterFilters,
  type PortalUiActions,
  type RosterFilter,
} from "./PortalUiState";
import {
  attest,
  cachedActiveSession,
  cachedFacultyCourses,
  cachedFacultyIdentity,
  cachedFacultyRegister,
  cachedSessionHistory,
  cachedTodayClasses,
  cachedRoster,
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
  prepareOfflineSessions,
  queueOfflineSessionClose,
  reconcileOfflineSessions,
  startSession,
  startCachedOfflineSession,
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

type PortalDataState = {
  classes: FacultyClass[];
  facultyCourses: FacultyCourse[];
  sessionHistory: FacultySessionRecord[];
  selectedRegisterOfferingId: string | null;
  register: FacultyRegister | null;
  session: FacultySession | null;
  roster: RosterStudent[];
  facultyIdentity: FacultyIdentity | null;
  loginLoading: boolean;
  loading: boolean;
  error: string | null;
  errorKind: PortalErrorKind | null;
  passwordChangeRequired: boolean;
  online: boolean;
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
  clearError: () => void;
};

/** Everything `useFacultyPortal()` historically returned. */
export type FacultyPortalState = PortalDataState & PortalUiActions & {
  loginEmail: string;
  loginPassword: string;
  projectorMode: boolean;
  confirmStudent: RosterStudent | null;
  attestationReason: string;
  rosterQuery: string;
  rosterFilter: RosterFilter;
  registerQuery: string;
  registerDateFilter: string;
  thresholdPercent: number;
};

const FacultyPortalContext = createContext<PortalDataState | null>(null);

export function FacultyPortalProvider({ children }: { children: React.ReactNode }) {
  return (
    <PortalUiProvider>
      <FacultyPortalDataProvider>{children}</FacultyPortalDataProvider>
    </PortalUiProvider>
  );
}

function FacultyPortalDataProvider({ children }: { children: React.ReactNode }) {
  // Stable actions only: this provider must not re-render when UI fields change.
  const ui = usePortalUiActions();
  const [classes, setClasses] = useState<FacultyClass[]>([]);
  const [facultyCourses, setFacultyCourses] = useState<FacultyCourse[]>([]);
  const [sessionHistory, setSessionHistory] = useState<FacultySessionRecord[]>([]);
  const [selectedRegisterOfferingId, setSelectedRegisterOfferingId] = useState<string | null>(null);
  const [register, setRegister] = useState<FacultyRegister | null>(null);
  const [session, setSession] = useState<FacultySession | null>(null);
  const [roster, setRoster] = useState<RosterStudent[]>([]);
  const [facultyIdentity, setFacultyIdentity] = useState<FacultyIdentity | null>(null);
  const [loginLoading, setLoginLoading] = useState(false);
  const [loading, setLoading] = useState(false);
  // Read through a ref so refreshActiveSession stays stable and the live-update
  // socket is not torn down every time a page-level load toggles `loading`.
  const loadingRef = useRef(false);
  useEffect(() => { loadingRef.current = loading; }, [loading]);
  const [portalError, setPortalError] = useState<PortalError | null>(null);
  const [passwordChangeFlag, setPasswordChangeFlag] = useState(false);
  const [online, setOnline] = useState(true);
  const error = portalError?.message ?? null;
  const errorKind = portalError?.kind ?? null;
  const setError = useCallback((message: string | null) => {
    setPortalError(message ? { kind: "generic", message } : null);
  }, []);

  const clearError = useCallback(() => setPortalError(null), []);

  const resetWorkspace = useCallback(() => {
    clearFacultyIdentity();
    clearCachedActiveSession();
    setFacultyIdentity(null);
    setClasses([]);
    setFacultyCourses([]);
    setSessionHistory([]);
    setSelectedRegisterOfferingId(null);
    setRegister(null);
    setSession(null);
    setRoster([]);
    setPasswordChangeFlag(false);
    ui.setProjectorMode(false);
  }, [ui]);

  /** Records a failure with its category; expired sessions return to sign-in. */
  const reportFailure = useCallback((exception: unknown, fallback: string): PortalError => {
    const failure = classifyPortalError(exception, fallback, typeof navigator === "undefined" || navigator.onLine);
    if (failure.kind === "session_expired") {
      resetWorkspace();
    } else if (failure.kind === "password_change_required") {
      setPasswordChangeFlag(true);
    }
    setPortalError(failure);
    return failure;
  }, [resetWorkspace]);

  const defaultRegisterOfferingId = useCallback((courseList = facultyCourses, classList = classes) => {
    return courseList[0]?.course_offering_id ?? classList[0]?.course_offering_id ??
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
      reportFailure(exception, "Register unavailable");
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

      const prepared = await prepareOfflineSessions();
      await Promise.all(prepared.map((item) => fetchRoster(item.id)));

      const selected = selectedRegisterOfferingId ?? defaultRegisterOfferingId(courses, today);
      if (selected) {
        setSelectedRegisterOfferingId(selected);
        setRegister(await fetchFacultyRegister(selected));
      }

      const cached = cachedActiveSession();
      const activeRecord = history.find((item) => item.state === "ACTIVE");
      const activeSessionId = cached?.id ?? activeRecord?.id ?? null;
      if (activeSessionId) {
        const updatedSession = await fetchSession(activeSessionId);
        if (updatedSession) {
          setSession(updatedSession);
          setRoster(await fetchRoster(updatedSession.id));
        } else {
          setSession(null);
          setRoster([]);
          clearCachedActiveSession();
        }
      } else {
        setSession(null);
        setRoster([]);
        clearCachedActiveSession();
      }
    } catch (exception) {
      const failure = reportFailure(exception, "Unable to sync");
      if (failure.kind !== "session_expired") {
        setClasses(cachedTodayClasses());
        setFacultyCourses(cachedFacultyCourses());
        setSessionHistory(cachedSessionHistory());
      }
    } finally {
      setLoading(false);
    }
  }, [defaultRegisterOfferingId, reportFailure, selectedRegisterOfferingId]);

  const submitFacultyLogin = useCallback(async () => {
    const { loginEmail, loginPassword } = ui.read();
    const email = loginEmail.trim().toLowerCase();
    if (!email || !loginPassword) {
      setError("Enter your Institution faculty email and password");
      return;
    }
    setLoginLoading(true);
    setError(null);
    try {
      const identity = await loginFaculty(email, loginPassword);
      setFacultyIdentity(identity);
      setPasswordChangeFlag(identity.must_change_password);
      ui.setLoginPassword("");
      localStorage.setItem("faculty.lastLogin", email);
      if (!identity.must_change_password) await refresh();
    } catch (exception) {
      const failure = classifyPortalError(exception, "Faculty login failed", navigator.onLine);
      // A 401 here means wrong credentials, not an expired session.
      setPortalError(failure.kind === "session_expired" ? { kind: "generic", message: failure.message } : failure);
    } finally {
      setLoginLoading(false);
    }
  }, [refresh, setError, ui]);

  const switchFaculty = useCallback(async () => {
    try {
      await logoutFaculty();
    } catch {
      clearFacultyIdentity();
    }
    resetWorkspace();
    setError(null);
  }, [resetWorkspace, setError]);

  const updateProfile = useCallback(async (displayName: string, phoneNumber: string | null) => {
    setLoading(true);
    setError(null);
    try {
      setFacultyIdentity(await updateFacultyProfile(displayName, phoneNumber));
    } catch (exception) {
      reportFailure(exception, "Could not update profile");
      throw exception;
    } finally {
      setLoading(false);
    }
  }, [reportFailure, setError]);

  const changePassword = useCallback(async (currentPassword: string, newPassword: string) => {
    setLoading(true);
    setError(null);
    try {
      await changeFacultyPassword(currentPassword, newPassword);
      resetWorkspace();
    } catch (exception) {
      reportFailure(exception, "Could not change password");
      throw exception;
    } finally {
      setLoading(false);
    }
  }, [reportFailure, resetWorkspace, setError]);

  const refreshActiveSession = useCallback(async (sessionId: string | null) => {
    if (!sessionId || loadingRef.current) return;
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
    } catch (exception) {
      // Keep the active classroom view usable with the last local roster,
      // but an expired session must still send the user back to sign-in.
      const failure = classifyPortalError(exception, "", true);
      if (failure.kind === "session_expired") reportFailure(exception, "Your session has expired.");
    }
  }, [reportFailure]);

  const start = useCallback(async (courseOfferingId: string) => {
    setLoading(true);
    setError(null);
    try {
      const nextSession = navigator.onLine
        ? await startSession(courseOfferingId)
        : startCachedOfflineSession(courseOfferingId);
      setSession(nextSession);
      setRoster(navigator.onLine ? await fetchRoster(nextSession.id) : cachedRoster(nextSession.id));
      return true;
    } catch (exception) {
      if (navigator.onLine && (!(exception instanceof ApiRequestError) || exception.status >= 500)) {
        try {
          const offlineSession = startCachedOfflineSession(courseOfferingId);
          setSession(offlineSession);
          setRoster(cachedRoster(offlineSession.id));
          setOnline(false);
          return true;
        } catch {
          // Surface the original server error when no prepared session exists.
        }
      }
      reportFailure(exception, "Session unavailable");
      return false;
    } finally {
      setLoading(false);
    }
  }, [reportFailure, setError]);

  const endSession = useCallback(async () => {
    if (!session) return;
    setLoading(true);
    setError(null);
    try {
      if (!navigator.onLine || session.offline_pending_activation) {
        queueOfflineSessionClose(session);
      } else {
        await closeSession(session.id);
        setSessionHistory(await fetchSessionHistory());
      }
      setSession(null);
      setRoster([]);
      ui.setProjectorMode(false);
    } catch (exception) {
      reportFailure(exception, "Could not close attendance session");
    } finally {
      setLoading(false);
    }
  }, [reportFailure, session, setError, ui]);

  const confirmAttestation = useCallback(async () => {
    const { confirmStudent, attestationReason } = ui.read();
    if (!session || !confirmStudent) return;
    setLoading(true);
    setError(null);
    try {
      await attest(session.id, confirmStudent.student_id, attestationReason);
      setRoster(await fetchRoster(session.id));
      ui.setConfirmStudent(null);
      ui.setAttestationReason(defaultAttestationReason);
    } catch (exception) {
      reportFailure(exception, "Faculty attestation failed");
    } finally {
      setLoading(false);
    }
  }, [reportFailure, session, setError, ui]);

  const exportRegisterCsv = useCallback(() => {
    const { registerQuery, registerDateFilter } = ui.read();
    if (register) downloadRegisterCsv(register, registerQuery, registerDateFilter);
  }, [register, ui]);

  useEffect(() => {
    setOnline(navigator.onLine);
    const setOnlineState = () => {
      setOnline(navigator.onLine);
      if (navigator.onLine && cachedFacultyIdentity()) {
        void (async () => {
          try {
            const reconciled = await reconcileOfflineSessions();
            if (reconciled) {
              setSession(reconciled);
              setRoster(await fetchRoster(reconciled.id));
            }
            await refresh();
          } catch {
            // The next online event or manual sync retries queued operations.
          }
        })();
      }
    };
    window.addEventListener("online", setOnlineState);
    window.addEventListener("offline", setOnlineState);

    const savedFacultyLogin = localStorage.getItem("faculty.lastLogin");
    if (savedFacultyLogin) {
      ui.setLoginEmail(savedFacultyLogin);
    }
    const identity = cachedFacultyIdentity();
    setFacultyIdentity(identity);
    setClasses(cachedTodayClasses());
    const courses = cachedFacultyCourses();
    setFacultyCourses(courses);
    setSessionHistory(cachedSessionHistory());
    const active = cachedActiveSession();
    setSession(active);
    if (active) setRoster(cachedRoster(active.id));
    const selected = defaultRegisterOfferingId(courses, cachedTodayClasses());
    setSelectedRegisterOfferingId(selected);
    setRegister(cachedFacultyRegister(selected));
    void (async () => {
      try {
        const verified = await fetchFacultyProfile();
        if (!verified) {
          if (identity) {
            resetWorkspace();
            setPortalError({ kind: "session_expired", message: "Your session has expired. Sign in again to continue." });
          }
          return;
        }
        setFacultyIdentity(verified);
        setPasswordChangeFlag(verified.must_change_password);
        if (!verified.must_change_password) await refresh();
      } catch {
        // Offline faculty access may display only cached workspace data.
      }
    })();

    return () => {
      window.removeEventListener("online", setOnlineState);
      window.removeEventListener("offline", setOnlineState);
    };
  }, []);

  useSessionEvents(
    session && !session.closed_at ? session.id : null,
    online && facultyIdentity !== null,
    facultySessionEventUrl,
    refreshActiveSession,
  );

  const value = useMemo<PortalDataState>(() => ({
    classes, facultyCourses, sessionHistory, selectedRegisterOfferingId, register, session, roster,
    facultyIdentity, loginLoading, loading, error, errorKind,
    passwordChangeRequired: passwordChangeFlag || Boolean(facultyIdentity?.must_change_password),
    online, submitFacultyLogin, switchFaculty, updateProfile, changePassword, refresh, refreshRegister,
    start, endSession, confirmAttestation, exportRegisterCsv, clearError,
  }), [
    classes, facultyCourses, sessionHistory, selectedRegisterOfferingId, register, session, roster,
    facultyIdentity, loginLoading, loading, error, errorKind, passwordChangeFlag, online,
    submitFacultyLogin, switchFaculty, updateProfile, changePassword, refresh, refreshRegister,
    start, endSession, confirmAttestation, exportRegisterCsv, clearError,
  ]);

  return (
    <FacultyPortalContext.Provider value={value}>
      {children}
    </FacultyPortalContext.Provider>
  );
}

/** Server-backed data and actions only. Prefer this (plus a UI slice hook) in hot components. */
export function usePortalData(): PortalDataState {
  const context = useContext(FacultyPortalContext);
  if (!context) throw new Error("usePortalData must be used inside FacultyPortalProvider");
  return context;
}

/** Compatibility hook: data plus every UI slice. Subscribes to all of them. */
export function useFacultyPortal(): FacultyPortalState {
  const data = usePortalData();
  const actions = usePortalUiActions();
  const login = useLoginFields();
  const rosterFilters = useRosterFilters();
  const registerFilters = useRegisterFilters();
  const attestation = useAttestationUi();
  const projector = useProjectorUi();
  return useMemo(
    () => ({ ...data, ...actions, ...login, ...rosterFilters, ...registerFilters, ...attestation, ...projector }),
    [data, actions, login, rosterFilters, registerFilters, attestation, projector],
  );
}
