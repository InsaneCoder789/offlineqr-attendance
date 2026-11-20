"use client";

import { createContext, useCallback, useContext, useMemo, useRef, useState } from "react";
import type { RosterStudent } from "../api";

export type RosterFilter = "all" | "present" | "pending";
export const defaultAttestationReason = "Student device failure";
export const defaultThresholdPercent = 75;

type LoginFields = { loginEmail: string; loginPassword: string };
type RosterFilters = { rosterQuery: string; rosterFilter: RosterFilter };
type RegisterFilters = { registerQuery: string; registerDateFilter: string; thresholdPercent: number };
type AttestationUi = { confirmStudent: RosterStudent | null; attestationReason: string };
type ProjectorUi = { projectorMode: boolean };

export type PortalUiActions = {
  setLoginEmail: (value: string) => void;
  setLoginPassword: (value: string) => void;
  setProjectorMode: (value: boolean) => void;
  setConfirmStudent: (value: RosterStudent | null) => void;
  setAttestationReason: (value: string) => void;
  setRosterQuery: (value: string) => void;
  setRosterFilter: (value: RosterFilter) => void;
  setRegisterQuery: (value: string) => void;
  setRegisterDateFilter: (value: string) => void;
  setThresholdPercent: (value: number) => void;
  /** Latest values without subscribing; safe to call from callbacks. */
  read: () => LoginFields & RosterFilters & RegisterFilters & AttestationUi & ProjectorUi;
};

const LoginContext = createContext<LoginFields | null>(null);
const RosterContext = createContext<RosterFilters | null>(null);
const RegisterContext = createContext<RegisterFilters | null>(null);
const AttestationContext = createContext<AttestationUi | null>(null);
const ProjectorContext = createContext<ProjectorUi | null>(null);
const ActionsContext = createContext<PortalUiActions | null>(null);

/**
 * Pure UI state, kept apart from server data so typing in a field never
 * re-renders the QR panel and a roster update never re-renders the login form.
 * Each slice has its own context; actions are referentially stable.
 */
export function PortalUiProvider({ children }: { children: React.ReactNode }) {
  const [loginEmail, setLoginEmail] = useState("");
  const [loginPassword, setLoginPassword] = useState("");
  const [rosterQuery, setRosterQuery] = useState("");
  const [rosterFilter, setRosterFilter] = useState<RosterFilter>("all");
  const [registerQuery, setRegisterQuery] = useState("");
  const [registerDateFilter, setRegisterDateFilter] = useState("all");
  const [thresholdPercent, setThresholdPercent] = useState(defaultThresholdPercent);
  const [confirmStudent, setConfirmStudent] = useState<RosterStudent | null>(null);
  const [attestationReason, setAttestationReason] = useState(defaultAttestationReason);
  const [projectorMode, setProjectorMode] = useState(false);

  const latest = useRef({
    loginEmail, loginPassword, rosterQuery, rosterFilter, registerQuery, registerDateFilter,
    thresholdPercent, confirmStudent, attestationReason, projectorMode,
  });
  latest.current = {
    loginEmail, loginPassword, rosterQuery, rosterFilter, registerQuery, registerDateFilter,
    thresholdPercent, confirmStudent, attestationReason, projectorMode,
  };
  const read = useCallback(() => latest.current, []);

  const login = useMemo(() => ({ loginEmail, loginPassword }), [loginEmail, loginPassword]);
  const roster = useMemo(() => ({ rosterQuery, rosterFilter }), [rosterQuery, rosterFilter]);
  const register = useMemo(
    () => ({ registerQuery, registerDateFilter, thresholdPercent }),
    [registerQuery, registerDateFilter, thresholdPercent],
  );
  const attestation = useMemo(() => ({ confirmStudent, attestationReason }), [confirmStudent, attestationReason]);
  const projector = useMemo(() => ({ projectorMode }), [projectorMode]);
  // useState setters are stable, so this object never changes.
  const actions = useMemo<PortalUiActions>(() => ({
    setLoginEmail, setLoginPassword, setProjectorMode, setConfirmStudent, setAttestationReason,
    setRosterQuery, setRosterFilter, setRegisterQuery, setRegisterDateFilter, setThresholdPercent, read,
  }), [read]);

  return (
    <ActionsContext.Provider value={actions}>
      <LoginContext.Provider value={login}>
        <RosterContext.Provider value={roster}>
          <RegisterContext.Provider value={register}>
            <AttestationContext.Provider value={attestation}>
              <ProjectorContext.Provider value={projector}>{children}</ProjectorContext.Provider>
            </AttestationContext.Provider>
          </RegisterContext.Provider>
        </RosterContext.Provider>
      </LoginContext.Provider>
    </ActionsContext.Provider>
  );
}

function need<T>(value: T | null): T {
  if (!value) throw new Error("Portal UI hooks must be used inside PortalUiProvider");
  return value;
}

export const usePortalUiActions = () => need(useContext(ActionsContext));
export const useLoginFields = () => need(useContext(LoginContext));
export const useRosterFilters = () => need(useContext(RosterContext));
export const useRegisterFilters = () => need(useContext(RegisterContext));
export const useAttestationUi = () => need(useContext(AttestationContext));
export const useProjectorUi = () => need(useContext(ProjectorContext));
