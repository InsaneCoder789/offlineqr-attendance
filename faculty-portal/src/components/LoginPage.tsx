"use client";

import Image from "next/image";
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
  TriangleAlert,
  WifiOff,
} from "lucide-react";
import { useFacultyPortal } from "./FacultyPortalProvider";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Field, FieldDescription, FieldGroup, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";

const capabilities = [
  { icon: QrCode, label: "5-second signed QR rotation" },
  { icon: WifiOff, label: "Offline session continuity" },
  { icon: ShieldCheck, label: "Auditable faculty actions" },
];

export function LoginPage() {
  const {
    error,
    loginEmail,
    loginLoading,
    loginPassword,
    setLoginEmail,
    setLoginPassword,
    submitFacultyLogin,
  } = useFacultyPortal();
  const [showPassword, setShowPassword] = useState(false);

  function submit(event: React.FormEvent) {
    event.preventDefault();
    if (!loginLoading) void submitFacultyLogin();
  }

  return (
    <main className="relative isolate min-h-[100dvh] overflow-hidden bg-[#10251b] lg:grid lg:grid-cols-[minmax(0,1.15fr)_minmax(30rem,0.85fr)]">
      <Image
        src="/branding/kiit-campus-aerial.webp"
        alt="Aerial view of the KIIT campus"
        fill
        priority
        sizes="100vw"
        className="-z-20 object-cover object-center"
      />
      <div className="absolute inset-0 -z-10 bg-black/50 lg:bg-black/42" aria-hidden="true" />

      <section className="relative hidden min-h-[100dvh] p-10 text-white lg:flex lg:flex-col lg:justify-between xl:p-14">
        <div className="relative flex items-center gap-3">
          <span className="flex size-12 items-center justify-center rounded-lg bg-white">
            <Image src="/branding/kiit_logo.png" alt="KIIT" width={40} height={40} priority />
          </span>
          <div>
            <strong className="block text-sm font-semibold">KIIT Attendance</strong>
            <span className="text-xs text-white/65">Institutional teaching operations</span>
          </div>
        </div>

        <div className="relative max-w-2xl pb-4">
          <Badge className="mb-6 border-white/25 bg-black/20 text-white backdrop-blur-sm" variant="outline">Faculty workspace</Badge>
          <h1 className="max-w-2xl text-balance text-5xl font-semibold leading-[1.04] tracking-tight [text-shadow:0_2px_24px_rgba(0,0,0,0.35)] xl:text-6xl">Attendance that keeps teaching moving.</h1>
          <p className="mt-5 max-w-xl text-pretty text-lg leading-8 text-white/85">
            Start secure classroom sessions, monitor verified attendance, and reconcile offline proofs from one operational console.
          </p>
          <div className="mt-9 grid max-w-xl gap-3 sm:grid-cols-3">
            {capabilities.map(({ icon: Icon, label }) => (
              <div className="border-t border-white/20 pt-4" key={label}>
                <Icon className="mb-3 size-5 text-[#8ee5ac]" aria-hidden="true" />
                <span className="block text-sm leading-5 text-white/90">{label}</span>
              </div>
            ))}
          </div>
        </div>

        <div className="relative flex items-center justify-between border-t border-white/20 pt-5 text-xs text-white/75">
          <span>Capture locally. Verify centrally.</span>
          <span className="flex items-center gap-2"><CheckCircle2 className="size-4 text-[#78d79d]" />Offline-ready</span>
        </div>
      </section>

      <div className="flex items-center gap-3 px-5 py-6 text-white lg:hidden">
        <span className="flex size-11 items-center justify-center rounded-lg bg-white">
          <Image src="/branding/kiit_logo.png" alt="KIIT" width={36} height={36} priority />
        </span>
        <div>
          <strong className="block text-sm font-semibold">KIIT Attendance</strong>
          <span className="text-xs text-white/75">Faculty workspace</span>
        </div>
      </div>

      <section className="mt-28 flex min-h-[calc(100dvh-7rem)] items-center justify-center bg-background px-5 py-10 sm:mt-36 sm:px-8 lg:mt-0 lg:min-h-[100dvh] lg:border-l lg:border-white/15 lg:bg-background/97 lg:px-12 lg:py-12 lg:shadow-[-24px_0_80px_rgba(0,0,0,0.18)] lg:backdrop-blur-md">
        <div className="w-full max-w-md">
          <div className="mb-7">
            <p className="mb-2 text-xs font-semibold uppercase tracking-[0.14em] text-primary">Authorized access</p>
            <h2 className="text-balance text-3xl font-semibold tracking-tight sm:text-4xl">Welcome back</h2>
            <p className="mt-2 text-pretty leading-6 text-muted-foreground">Use your institutional account to open your assigned classes and active sessions.</p>
          </div>

          <div className="border-t pt-6">
            <div className="mb-6">
              <h3 className="text-lg font-semibold">Faculty sign in</h3>
              <p className="mt-1 text-sm text-muted-foreground">Only verified <strong className="font-medium text-foreground">@kiit.ac.in</strong> identities are accepted.</p>
            </div>
            <form onSubmit={submit}>
              <FieldGroup>
                <Field>
                  <FieldLabel htmlFor="faculty-email">KIIT email</FieldLabel>
                  <Input
                    id="faculty-email"
                    type="email"
                    value={loginEmail}
                    placeholder="name@kiit.ac.in"
                    autoComplete="username"
                    onChange={(event) => setLoginEmail(event.target.value)}
                    aria-invalid={Boolean(error)}
                  />
                </Field>
                <Field>
                  <div className="flex items-center justify-between gap-4">
                    <FieldLabel htmlFor="faculty-password">Password</FieldLabel>
                    <span className="text-xs text-muted-foreground">Case-sensitive</span>
                  </div>
                  <div className="relative">
                    <Input
                      id="faculty-password"
                      type={showPassword ? "text" : "password"}
                      value={loginPassword}
                      placeholder="Enter your password"
                      autoComplete="current-password"
                      className="pr-11"
                      onChange={(event) => setLoginPassword(event.target.value)}
                      aria-invalid={Boolean(error)}
                    />
                    <Button
                      type="button"
                      variant="ghost"
                      size="icon-sm"
                      className="absolute right-1.5 top-1.5"
                      aria-label={showPassword ? "Hide password" : "Show password"}
                      onClick={() => setShowPassword((value) => !value)}
                    >
                      {showPassword ? <EyeOff /> : <Eye />}
                    </Button>
                  </div>
                  <FieldDescription>Credentials are verified by the attendance service and are never stored in this browser.</FieldDescription>
                </Field>
                {error ? (
                  <Alert variant="destructive">
                    <TriangleAlert />
                    <AlertTitle>Sign-in failed</AlertTitle>
                    <AlertDescription>{error}</AlertDescription>
                  </Alert>
                ) : null}
                <Button type="submit" size="lg" disabled={loginLoading} className="w-full">
                  {loginLoading ? <RefreshCw data-icon="inline-start" className="animate-spin" /> : <LockKeyhole data-icon="inline-start" />}
                  {loginLoading ? "Verifying account" : "Open workspace"}
                  {!loginLoading ? <ArrowRight data-icon="inline-end" /> : null}
                </Button>
              </FieldGroup>
            </form>
          </div>

          <p className="mt-6 text-center text-xs leading-5 text-muted-foreground">Access is limited to classes, rosters, and controls assigned to your institutional identity.</p>
        </div>
      </section>
    </main>
  );
}
