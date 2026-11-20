"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import {
  AlertTriangle,
  ArrowRight,
  Eye,
  EyeOff,
  LockKeyhole,
  QrCode,
  RefreshCw,
  ShieldCheck,
  Timer,
  WifiOff,
} from "lucide-react";
import { usePortalData } from "./FacultyPortalProvider";
import { useLoginFields, usePortalUiActions } from "./PortalUiState";
import { PortalErrorAlert } from "./PortalErrorAlert";
import { BrandQrMotif } from "./BrandQrMotif";
import styles from "./dark-command.module.css";
import { Button } from "@/components/ui/button";
import { Field, FieldDescription, FieldGroup, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";

const trustPoints = [
  { icon: QrCode, title: "Signed QR, every 5 seconds", body: "Codes rotate so screenshots and forwards expire before they can be reused." },
  { icon: WifiOff, title: "Offline session continuity", body: "Keep teaching without a signal. Records reconcile when you reconnect." },
  { icon: ShieldCheck, title: "Auditable by design", body: "Every faculty action is recorded against your institutional identity." },
];

function retrySeconds(message: string | null): number {
  const match = message?.match(/in (\d+) seconds?/i);
  return match ? Number(match[1]) : 0;
}

export function LoginPage() {
  const { error, errorKind, loginLoading, submitFacultyLogin, online } = usePortalData();
  const { loginEmail, loginPassword } = useLoginFields();
  const { setLoginEmail, setLoginPassword } = usePortalUiActions();
  const submitting = useRef(false);
  const [showPassword, setShowPassword] = useState(false);
  const [capsLock, setCapsLock] = useState(false);
  const [touched, setTouched] = useState(false);
  const [remaining, setRemaining] = useState(0);

  // Lockout countdown seeded from the Retry-After wait the API folds into the message.
  useEffect(() => {
    if (errorKind !== "rate_limited") { setRemaining(0); return; }
    setRemaining(retrySeconds(error));
  }, [error, errorKind]);
  useEffect(() => {
    if (remaining <= 0) return;
    const timer = window.setInterval(() => setRemaining((value) => Math.max(0, value - 1)), 1000);
    return () => window.clearInterval(timer);
  }, [remaining > 0]); // eslint-disable-line react-hooks/exhaustive-deps

  const emailValid = /^\S+@\S+\.\S+$/.test(loginEmail.trim());
  const emailInvalid = touched && !emailValid;
  const locked = remaining > 0;
  const hasError = Boolean(error);

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setTouched(true);
    if (submitting.current || loginLoading || locked || !online || !emailValid) return;
    submitting.current = true;
    try {
      await submitFacultyLogin();
    } finally {
      submitting.current = false;
    }
  }

  return (
    <main className="silk-workspace silk-sign-in relative min-h-dvh bg-background text-foreground lg:grid lg:grid-cols-[minmax(25rem,0.8fr)_minmax(0,1.2fr)]">
      <div className={cn(styles.radial, "absolute inset-0 -z-20")} aria-hidden="true" />
      <div className={cn(styles.gridlines, "absolute inset-0 -z-10")} aria-hidden="true" />

      <section className="silk-sign-in-story relative order-2 hidden min-h-dvh flex-col justify-between border-l bg-muted p-10 lg:flex xl:p-14">
        <Link href="/" className="inline-flex w-fit items-center gap-3 rounded-xl text-lg font-semibold tracking-tight text-foreground focus-visible:outline-2 focus-visible:outline-primary"><span className="flex size-10 items-center justify-center rounded-xl bg-primary text-primary-foreground"><QrCode className="size-5" aria-hidden="true" /></span>OfflineQR</Link>
        <div className="grid items-center gap-10 xl:grid-cols-[minmax(0,1fr)_16rem]">
          <div>
            <p className="mb-5 text-xs font-bold uppercase tracking-[0.22em] text-primary">Faculty command centre</p>
            <h1 className="text-balance text-[clamp(2.75rem,5.2vw,5.5rem)] font-extrabold leading-[0.95] tracking-[-0.045em]">Attendance, <span className={styles.glowText}>verified</span> in the room.</h1>
            <p className="mt-6 max-w-lg text-pretty text-base leading-7 text-muted-foreground">Start sessions, verify presence, reconcile offline. One secure institutional console.</p>
          </div>
          <div className="hidden w-64 max-w-full xl:block" aria-hidden="true"><BrandQrMotif /></div>
        </div>
        <ul className="grid max-w-3xl gap-4 xl:grid-cols-3">
          {trustPoints.map(({ icon: Icon, title, body }) => (
            <li key={title} className={cn(styles.glass, "rounded-2xl p-4")}>
              <Icon className="mb-3 size-5 text-primary" aria-hidden="true" />
              <strong className="block text-sm font-semibold leading-5">{title}</strong>
              <span className="mt-1 block text-xs leading-5 text-muted-foreground">{body}</span>
            </li>
          ))}
        </ul>
      </section>

      <section className="order-1 flex min-h-dvh items-center justify-center px-5 py-8 sm:px-8">
        <div className="w-full max-w-md">
          <Link href="/" className="mb-6 inline-flex items-center gap-2 text-lg font-semibold text-foreground lg:hidden"><span className="flex size-9 items-center justify-center rounded-xl bg-primary text-primary-foreground"><QrCode className="size-5" aria-hidden="true" /></span>OfflineQR</Link>
          <p className="mb-2 text-xs font-semibold uppercase tracking-[0.18em] text-primary">Authorized institutional access</p>
          <h2 className="text-balance text-fluid-2xl font-bold leading-tight tracking-tight">Faculty sign in</h2>
          <p className="mt-2 text-pretty text-sm leading-6 text-muted-foreground">Open your assigned classes, active sessions, and verified attendance records.</p>

          {!online ? (
            <div role="status" className="mt-5 flex items-start gap-3 rounded-xl border border-warning/40 bg-warning/10 p-3 text-sm">
              <WifiOff className="mt-0.5 size-4 shrink-0 text-warning" aria-hidden="true" />
              <span><strong className="font-semibold">You are offline.</strong> <span className="text-muted-foreground">Sign-in needs a connection. Existing sessions stay available.</span></span>
            </div>
          ) : null}

          <form onSubmit={(event) => void submit(event)} className="mt-6" aria-busy={loginLoading} noValidate>
            <FieldGroup className="gap-5">
              <Field>
                <FieldLabel htmlFor="faculty-email">Institutional email</FieldLabel>
                <Input id="faculty-email" type="email" value={loginEmail} placeholder="name@institution.edu" autoComplete="username" className="h-12 rounded-xl bg-background/60 text-base" onChange={(event) => setLoginEmail(event.target.value)} onBlur={() => setTouched(true)} aria-invalid={hasError || emailInvalid} aria-describedby={emailInvalid ? "email-hint" : hasError ? "login-error" : undefined} disabled={loginLoading} required />
                {emailInvalid ? <p id="email-hint" className="text-xs text-destructive" role="alert">Enter a full address such as name@institution.edu.</p> : null}
              </Field>
              <Field>
                <div className="flex items-center justify-between gap-3">
                  <FieldLabel htmlFor="faculty-password">Password</FieldLabel>
                  <span className="text-xs text-muted-foreground" id="password-hint">Case sensitive</span>
                </div>
                <div className="relative">
                  <Input id="faculty-password" type={showPassword ? "text" : "password"} value={loginPassword} placeholder="Enter your password" autoComplete="current-password" className="h-12 rounded-xl bg-background/60 pr-12 text-base" onChange={(event) => setLoginPassword(event.target.value)} onKeyUp={(event) => setCapsLock(event.getModifierState("CapsLock"))} onKeyDown={(event) => setCapsLock(event.getModifierState("CapsLock"))} onBlur={() => setCapsLock(false)} aria-invalid={hasError} aria-describedby={hasError ? "login-error" : "password-hint"} disabled={loginLoading} required />
                  <Button type="button" variant="ghost" size="icon" className="absolute right-1 top-1/2 -translate-y-1/2" aria-label={showPassword ? "Hide password" : "Show password"} aria-pressed={showPassword} disabled={loginLoading} onClick={() => setShowPassword((value) => !value)}>
                    {showPassword ? <EyeOff /> : <Eye />}
                  </Button>
                </div>
                {capsLock ? <p className="flex items-center gap-1.5 text-xs text-warning" role="status"><AlertTriangle className="size-3.5" aria-hidden="true" />Caps Lock is on.</p> : null}
                <FieldDescription className="text-xs leading-5">Credentials are verified by the attendance service and are never stored in this browser.</FieldDescription>
              </Field>
              {error ? (
                <div id="login-error" role="alert">
                  <PortalErrorAlert message={error} kind={errorKind} title={errorKind === "generic" || errorKind === null ? "Sign-in failed" : undefined} showSettingsLink={false} />
                  {errorKind === "rate_limited" ? (
                    <p className="mt-2 flex items-center gap-2 text-xs text-muted-foreground"><Timer className="size-3.5 text-warning" aria-hidden="true" />{locked ? <>Too many attempts. Try again in <strong className="tabular-nums text-foreground">{remaining}s</strong>.</> : "Too many attempts. The account is temporarily locked; wait a few minutes before trying again."}</p>
                  ) : null}
                </div>
              ) : null}
              <Button type="submit" size="lg" disabled={loginLoading || locked || !online} className="h-12 w-full rounded-xl text-sm font-semibold shadow-[0_0_32px_-8px_var(--primary)]">
                {loginLoading ? <RefreshCw data-icon="inline-start" className="animate-spin" /> : <LockKeyhole data-icon="inline-start" />}
                {loginLoading ? "Verifying account" : locked ? `Locked for ${remaining}s` : "Enter faculty portal"}
                {!loginLoading && !locked ? <ArrowRight data-icon="inline-end" /> : null}
              </Button>
            </FieldGroup>
          </form>
          <p className="mt-6 border-t pt-4 text-center text-xs leading-5 text-muted-foreground">Access is limited to classes, rosters, and controls assigned to your institutional identity.</p>
        </div>
      </section>
    </main>
  );
}
