"use client";

import Image from "next/image";
import Link from "next/link";
import { useState } from "react";
import {
  ArrowRight,
  CheckCircle2,
  Eye,
  EyeOff,
  LockKeyhole,
  QrCode,
  RefreshCw,
  ShieldCheck,
  WifiOff,
} from "lucide-react";
import { usePortalData } from "./FacultyPortalProvider";
import { useLoginFields, usePortalUiActions } from "./PortalUiState";
import { PortalErrorAlert } from "./PortalErrorAlert";
import { Button } from "@/components/ui/button";
import { Field, FieldDescription, FieldGroup, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";

const capabilities = [
  { icon: QrCode, label: "5-second signed QR rotation" },
  { icon: WifiOff, label: "Offline session continuity" },
  { icon: ShieldCheck, label: "Auditable faculty actions" },
];

export function LoginPage() {
  const { error, errorKind, loginLoading, submitFacultyLogin } = usePortalData();
  const { loginEmail, loginPassword } = useLoginFields();
  const { setLoginEmail, setLoginPassword } = usePortalUiActions();
  const [showPassword, setShowPassword] = useState(false);

  function submit(event: React.FormEvent) {
    event.preventDefault();
    if (!loginLoading) void submitFacultyLogin();
  }

  return (
    <main className="relative isolate min-h-dvh overflow-x-clip bg-muted/40 lg:grid lg:grid-cols-[minmax(0,1.1fr)_minmax(26rem,0.9fr)] lg:bg-[#10251b]">
      <Image src="/branding/classroom-editorial.webp" alt="" fill priority sizes="100vw" className="-z-20 hidden object-cover object-center lg:block" />
      <div className="absolute inset-0 -z-10 hidden bg-black/45 lg:block" aria-hidden="true" />

      <section className="relative hidden min-h-dvh p-10 text-white lg:flex lg:flex-col lg:justify-between xl:p-14">
        <Link href="/" className="inline-flex items-center gap-3 text-2xl font-semibold text-white"><QrCode aria-hidden="true" />OfflineQR</Link>
        <div className="max-w-2xl pb-4">
          <p className="mb-5 text-xs font-bold uppercase tracking-[0.2em] text-[#9ee5b5]">Faculty attendance · Academic operations</p>
          <h1 className="text-balance text-fluid-3xl font-semibold leading-[1.02] [text-shadow:0_3px_28px_rgba(0,0,0,0.42)]">Attendance built for the rhythm of teaching.</h1>
          <p className="mt-5 max-w-xl text-pretty text-base leading-7 text-white/85">Start sessions. Verify presence. Reconcile offline. One secure institutional console.</p>
          <div className="mt-10 grid max-w-2xl gap-4 sm:grid-cols-3">
            {capabilities.map(({ icon: Icon, label }) => (
              <div className="border-t border-white/35 pt-4" key={label}>
                <Icon className="mb-3 size-5 text-[#8ee5ac]" aria-hidden="true" />
                <span className="block text-xs font-semibold leading-5 text-white/92">{label}</span>
              </div>
            ))}
          </div>
        </div>
        <div className="flex items-center justify-between border-t border-white/25 pt-5 text-xs font-medium text-white/75">
          <span>Capture locally · Verify centrally</span>
          <span className="flex items-center gap-2"><CheckCircle2 className="size-4 text-[#78d79d]" aria-hidden="true" />Offline ready</span>
        </div>
      </section>

      <section className="flex min-h-dvh items-center justify-center px-4 py-8 sm:px-8 lg:bg-background/97 lg:backdrop-blur-md">
        <div className="w-full max-w-md rounded-2xl border bg-card p-5 shadow-sm sm:p-8 lg:border-0 lg:bg-transparent lg:p-0 lg:shadow-none">
          <Link href="/" className="mb-6 inline-flex items-center gap-2 text-lg font-semibold text-primary lg:hidden"><QrCode className="size-5" aria-hidden="true" />OfflineQR</Link>
          <p className="mb-2 text-xs font-semibold text-primary">Authorized institutional access</p>
          <h2 className="text-balance text-fluid-2xl font-semibold leading-tight">Faculty sign in</h2>
          <p className="mt-2 text-pretty text-sm leading-6 text-muted-foreground">Open your assigned classes, active sessions, and verified attendance records.</p>

          <form onSubmit={submit} className="mt-6" aria-busy={loginLoading}>
            <FieldGroup className="gap-5">
              <Field>
                <FieldLabel htmlFor="faculty-email">Institutional email</FieldLabel>
                <Input id="faculty-email" type="email" value={loginEmail} placeholder="name@institution.edu" autoComplete="username" className="h-12 text-base" onChange={(event) => setLoginEmail(event.target.value)} aria-invalid={Boolean(error)} aria-describedby={error ? "login-error" : undefined} disabled={loginLoading} required />
              </Field>
              <Field>
                <div className="flex items-center justify-between gap-3">
                  <FieldLabel htmlFor="faculty-password">Password</FieldLabel>
                  <span className="text-xs text-muted-foreground" id="password-hint">Case sensitive</span>
                </div>
                <div className="relative">
                  <Input id="faculty-password" type={showPassword ? "text" : "password"} value={loginPassword} placeholder="Enter your password" autoComplete="current-password" className="h-12 pr-12 text-base" onChange={(event) => setLoginPassword(event.target.value)} aria-invalid={Boolean(error)} aria-describedby={error ? "login-error" : undefined} disabled={loginLoading} required />
                  <Button type="button" variant="ghost" size="icon" className="absolute right-1 top-1/2 -translate-y-1/2" aria-label={showPassword ? "Hide password" : "Show password"} aria-pressed={showPassword} onClick={() => setShowPassword((value) => !value)}>
                    {showPassword ? <EyeOff /> : <Eye />}
                  </Button>
                </div>
                <FieldDescription className="text-xs leading-5">Credentials are verified by the attendance service and are never stored in this browser.</FieldDescription>
              </Field>
              {error ? (
                <div id="login-error" role="alert">
                  <PortalErrorAlert message={error} kind={errorKind} title={errorKind === "generic" || errorKind === null ? "Sign-in failed" : undefined} showSettingsLink={false} />
                  {errorKind === "rate_limited" ? <p className="mt-2 text-xs text-muted-foreground">Too many attempts. The account is temporarily locked; wait a few minutes before trying again.</p> : null}
                </div>
              ) : null}
              <Button type="submit" size="lg" disabled={loginLoading} className="h-12 w-full text-sm font-semibold">
                {loginLoading ? <RefreshCw data-icon="inline-start" className="animate-spin" /> : <LockKeyhole data-icon="inline-start" />}
                {loginLoading ? "Verifying account" : "Enter faculty portal"}
                {!loginLoading ? <ArrowRight data-icon="inline-end" /> : null}
              </Button>
            </FieldGroup>
          </form>
          <p className="mt-6 border-t pt-4 text-center text-xs leading-5 text-muted-foreground">Access is limited to classes, rosters, and controls assigned to your institutional identity.</p>
        </div>
      </section>
    </main>
  );
}
