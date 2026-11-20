"use client";

import { useEffect, useRef, useState } from "react";
import { Check, Eye, EyeOff, KeyRound, LogOut, Monitor, RefreshCw, Save, ShieldCheck, UserRound, Wifi, WifiOff, X } from "lucide-react";
import { toast } from "sonner";
import { facultyInitials } from "@/lib/format";
import { usePortalData } from "./FacultyPortalProvider";
import styles from "./dark-command.module.css";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Field, FieldDescription, FieldGroup, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { ErrorPanel, LoadingPanel, PageIntro, StatusBadge } from "./PortalUI";
import { cn } from "@/lib/utils";

const rules = [
  { label: "14 or more characters", test: (value: string) => value.length >= 14 },
  { label: "Upper and lower case letters", test: (value: string) => /[a-z]/.test(value) && /[A-Z]/.test(value) },
  { label: "A number and a symbol", test: (value: string) => /\d/.test(value) && /[^A-Za-z0-9]/.test(value) },
  { label: "18+ characters for extra strength", test: (value: string) => value.length >= 18 },
];

function passwordStrength(value: string) {
  let score = 0;
  if (value.length >= 14) score++;
  if (value.length >= 18) score++;
  if (/[a-z]/.test(value) && /[A-Z]/.test(value)) score++;
  if (/\d/.test(value) && /[^A-Za-z0-9]/.test(value)) score++;
  if (value.length < 14) score = Math.min(score, 1);
  const labels = ["Too short", "Weak", "Fair", "Good", "Strong"];
  const colors = ["bg-destructive", "bg-destructive", "bg-warning", "bg-success", "bg-success"];
  return { score, label: labels[score], color: colors[score] };
}

function browserLabel(agent: string) {
  const browser = /Edg\//.test(agent) ? "Edge" : /Chrome\//.test(agent) ? "Chrome" : /Firefox\//.test(agent) ? "Firefox" : /Safari\//.test(agent) ? "Safari" : "Browser";
  const os = /iPhone|iPad/.test(agent) ? "iOS" : /Android/.test(agent) ? "Android" : /Mac OS/.test(agent) ? "macOS" : /Windows/.test(agent) ? "Windows" : /Linux/.test(agent) ? "Linux" : "this device";
  return `${browser} on ${os}`;
}

function SectionCard({ icon: Icon, title, description, children, danger = false, id }: { icon: typeof UserRound; title: string; description: string; children: React.ReactNode; danger?: boolean; id?: string }) {
  return (
    <section className={cn(danger ? styles.glassDanger : styles.glass, "rounded-3xl p-5 sm:p-7")} aria-labelledby={id}>
      <header className="mb-6 flex items-start gap-3">
        <span className={cn("flex size-10 shrink-0 items-center justify-center rounded-xl", danger ? "bg-destructive/15 text-destructive" : "bg-primary/12 text-primary")}><Icon className="size-5" aria-hidden="true" /></span>
        <div className="min-w-0">
          <h2 id={id} className={cn("text-lg font-semibold tracking-tight", danger && "text-destructive")}>{title}</h2>
          <p className="mt-0.5 text-sm text-muted-foreground">{description}</p>
        </div>
      </header>
      {children}
    </section>
  );
}

export function SettingsPage() {
  const { classes, facultyIdentity, online, switchFaculty, updateProfile, changePassword, loading, passwordChangeRequired, error, refresh } = usePortalData();
  const [showNew, setShowNew] = useState(false);
  const savedName = facultyIdentity?.display_name ?? "";
  const savedPhone = facultyIdentity?.phone_number ?? "";
  const [displayName, setDisplayName] = useState(savedName);
  const [phoneNumber, setPhoneNumber] = useState(savedPhone);
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [signOutOpen, setSignOutOpen] = useState(false);
  const [saving, setSaving] = useState<"profile" | "password" | null>(null);
  const saveInFlight = useRef(false);
  const [agent, setAgent] = useState("");

  useEffect(() => {
    setDisplayName(savedName);
    setPhoneNumber(savedPhone);
  }, [savedName, savedPhone]);
  useEffect(() => { setAgent(navigator.userAgent); }, []);

  async function submitProfile(event: React.FormEvent) {
    event.preventDefault();
    if (!online || loading || !dirty || saveInFlight.current) return;
    saveInFlight.current = true;
    setSaving("profile");
    try {
      await updateProfile(displayName, phoneNumber || null);
      toast.success("Faculty profile updated");
    } catch { /* Provider exposes the service error in the shell. */ } finally {
      saveInFlight.current = false;
      setSaving(null);
    }
  }

  async function submitPassword(event: React.FormEvent) {
    event.preventDefault();
    if (!online || loading || saveInFlight.current) return;
    saveInFlight.current = true;
    setSaving("password");
    try {
      await changePassword(currentPassword, newPassword);
      setCurrentPassword("");
      setNewPassword("");
      toast.success("Password updated. Sign in again to continue.");
    } catch { /* Provider exposes the service error in the shell. */ } finally {
      saveInFlight.current = false;
      setSaving(null);
    }
  }

  const strength = passwordStrength(newPassword);
  const dirty = displayName !== savedName || phoneNumber !== savedPhone;
  const readyClasses = classes.filter((course) => course.offline_ready).length;

  const facts = [
    ["Faculty ID", facultyIdentity?.employee_code ?? facultyIdentity?.id ?? "Unavailable"],
    ["Designation", facultyIdentity?.designation ?? "Pending verification"],
    ["Organizational unit", facultyIdentity?.org_unit ?? "Not assigned"],
    ["Offline readiness", `${readyClasses} of ${classes.length} classes`],
  ];

  if (!facultyIdentity && loading) return (
    <div className="grid gap-5" aria-busy="true"><LoadingPanel rows={1} label="Loading profile" className="p-0" /><div className="grid gap-5 xl:grid-cols-[minmax(18rem,0.7fr)_minmax(0,1.3fr)]"><div className={cn(styles.glass, "h-72 animate-pulse rounded-3xl")} /><div className={cn(styles.glass, "h-96 animate-pulse rounded-3xl")} /></div></div>
  );
  if (!facultyIdentity) return <ErrorPanel title={online ? "Profile unavailable" : "You are offline"} message={error ?? "Your faculty profile could not be loaded."} onRetry={() => void refresh()} />;

  return (
    <>
      {!online ? <ErrorPanel className="m-0" title="You are offline" message="Profile and password changes need a connection. Saved details are shown read-only." /> : null}
      <PageIntro
        eyebrow="Account controls"
        title="Profile and security"
        description="Manage faculty contact information, password security, and this browser session."
        actions={<StatusBadge tone={online ? "success" : "warning"} icon={online ? Wifi : WifiOff}>{online ? "Connected" : "Offline mode"}</StatusBadge>}
      />

      <div className="grid grid-cols-1 items-start gap-5 xl:grid-cols-[minmax(18rem,0.7fr)_minmax(0,1.3fr)]">
        <aside className={cn(styles.glass, "min-w-0 rounded-3xl p-5 sm:p-7 xl:sticky xl:top-4")}>
          <div className={cn("flex size-16 items-center justify-center rounded-2xl bg-primary/12 text-2xl font-extrabold ring-1 ring-primary/30", styles.glowText)}>{facultyInitials(facultyIdentity)}</div>
          <h2 className="mt-4 [overflow-wrap:anywhere] text-xl font-semibold">{facultyIdentity.display_name ?? "Faculty"}</h2>
          <p className="mt-1 break-all text-sm text-muted-foreground">{facultyIdentity.institutional_email}</p>
          <div className="mt-6 flex flex-col">
            {facts.map(([label, value]) => (
              <div className="grid grid-cols-1 gap-1 border-t py-3 sm:grid-cols-[9rem_minmax(0,1fr)] xl:grid-cols-1 2xl:grid-cols-[9rem_minmax(0,1fr)]" key={label}>
                <span className="text-xs text-muted-foreground">{label}</span>
                <strong className="[overflow-wrap:anywhere] text-sm font-medium">{value}</strong>
              </div>
            ))}
          </div>
        </aside>

        <div className="grid min-w-0 gap-5">
          <SectionCard icon={UserRound} title="Profile details" description="Keep your faculty directory information current." id="profile-heading">
            <form id="profile-form" onSubmit={(event) => void submitProfile(event)}>
              <FieldGroup>
                <Field><FieldLabel htmlFor="display-name">Display name</FieldLabel><Input id="display-name" className="h-11 rounded-xl" value={displayName} onChange={(event) => setDisplayName(event.target.value)} autoComplete="name" disabled={!online || saving === "profile"} required /></Field>
                <Field><FieldLabel htmlFor="phone-number">Phone number</FieldLabel><Input id="phone-number" className="h-11 rounded-xl" value={phoneNumber} onChange={(event) => setPhoneNumber(event.target.value)} autoComplete="tel" inputMode="tel" placeholder="Optional institutional contact" disabled={!online || saving === "profile"} /></Field>
                <Button disabled={loading || saving !== null || !online || !dirty} type="submit" className="w-fit max-sm:w-full">{saving === "profile" ? <RefreshCw data-icon="inline-start" className="animate-spin" /> : <Save data-icon="inline-start" />}Save profile</Button>
              </FieldGroup>
            </form>
          </SectionCard>

          <SectionCard icon={KeyRound} title="Change password" description="Use a unique password of at least 14 characters." id="password-heading">
            <form onSubmit={(event) => void submitPassword(event)}>
              <FieldGroup>
                <Field><FieldLabel htmlFor="current-password">Current password</FieldLabel><Input id="current-password" className="h-11 rounded-xl" type="password" value={currentPassword} onChange={(event) => setCurrentPassword(event.target.value)} autoComplete="current-password" autoFocus={passwordChangeRequired} required /></Field>
                <Field><FieldLabel htmlFor="new-password">New password</FieldLabel><Input id="new-password" className="h-11 rounded-xl" type={showNew ? "text" : "password"} value={newPassword} onChange={(event) => setNewPassword(event.target.value)} autoComplete="new-password" minLength={14} required />
                  <button type="button" className="inline-flex min-h-11 w-fit items-center gap-2 rounded-lg text-xs font-medium text-muted-foreground underline-offset-4 hover:text-foreground hover:underline" aria-pressed={showNew} onClick={() => setShowNew((v) => !v)}>{showNew ? <EyeOff className="size-4" /> : <Eye className="size-4" />}{showNew ? "Hide" : "Show"} new password</button>
                  <div role="status" aria-live="polite">
                    <div className="grid grid-cols-4 gap-1.5" aria-hidden="true">{[1, 2, 3, 4].map((step) => <div key={step} className={cn("h-1.5 rounded-full transition-colors", strength.score >= step ? strength.color : "bg-muted")} />)}</div>
                    <p className="mt-2 text-xs text-muted-foreground">{newPassword ? `Strength: ${strength.label}` : "Use 14 or more characters with a mix of letters, numbers and symbols."}</p>
                  </div>
                  <ul className="grid gap-1.5 sm:grid-cols-2" aria-label="Password rules">
                    {rules.map((rule) => {
                      const met = rule.test(newPassword);
                      return <li key={rule.label} className={cn("flex items-center gap-2 text-xs", met ? "text-success" : "text-muted-foreground")}>{met ? <Check className="size-3.5" aria-hidden="true" /> : <X className="size-3.5 opacity-60" aria-hidden="true" />}<span>{rule.label}<span className="sr-only">{met ? " met" : " not met"}</span></span></li>;
                    })}
                  </ul>
                  <FieldDescription>Changing your password ends the current faculty session on this browser.</FieldDescription></Field>
                <Button disabled={loading || saving !== null || !online} type="submit" className="w-fit max-sm:w-full">{saving === "password" ? <RefreshCw data-icon="inline-start" className="animate-spin" /> : <ShieldCheck data-icon="inline-start" />}Update password</Button>
              </FieldGroup>
            </form>
          </SectionCard>

          <SectionCard icon={Monitor} title="Session and security" description="The browser currently signed in to the faculty portal." id="session-heading">
            <dl className="grid gap-px overflow-hidden rounded-2xl border bg-border sm:grid-cols-3">
              {[["This device", agent ? browserLabel(agent) : "Detecting"], ["Connection", online ? "Online" : "Offline"], ["Offline-ready", `${readyClasses} of ${classes.length} classes`]].map(([label, value]) => (
                <div key={label} className="min-w-0 bg-card/80 px-4 py-3"><dt className="text-xs text-muted-foreground">{label}</dt><dd className="mt-1 break-words text-sm font-semibold">{value}</dd></div>
              ))}
            </dl>
          </SectionCard>

          <SectionCard icon={LogOut} danger title="Danger zone" description="Signing out removes this faculty session from this browser. Unsynced offline work stays on the device." id="danger-zone">
            <Button variant="destructive" className="max-sm:w-full" onClick={() => setSignOutOpen(true)}><LogOut data-icon="inline-start" />Sign out of portal</Button>
          </SectionCard>
        </div>
      </div>

      {dirty ? (
        <div className="sticky bottom-[calc(var(--bottom-nav-h,0px)+0.75rem+env(safe-area-inset-bottom))] z-20 mx-auto flex w-full max-w-2xl flex-wrap items-center justify-between md:bottom-3 gap-3 rounded-2xl border border-primary/40 bg-popover/95 p-3 shadow-[0_18px_60px_-20px_var(--primary)] backdrop-blur" role="region" aria-label="Unsaved profile changes">
          <p className="min-w-0 pl-1 text-sm font-medium">Unsaved changes</p>
          <div className="flex flex-wrap gap-2">
            <Button type="button" variant="ghost" disabled={saving === "profile"} onClick={() => { setDisplayName(facultyIdentity.display_name ?? ""); setPhoneNumber(facultyIdentity.phone_number ?? ""); }}>Discard</Button>
            <Button type="submit" form="profile-form" disabled={loading || saving !== null || !online}>{saving === "profile" ? <RefreshCw data-icon="inline-start" className="animate-spin" /> : <Save data-icon="inline-start" />}Save changes</Button>
          </div>
        </div>
      ) : null}

      <Dialog open={signOutOpen} onOpenChange={setSignOutOpen}>
        <DialogContent>
          <DialogHeader><DialogTitle>Sign out of the portal?</DialogTitle><DialogDescription>This ends the faculty session in this browser. Pending attendance changes must sync before you can sign out.</DialogDescription></DialogHeader>
          <DialogFooter><Button variant="outline" onClick={() => setSignOutOpen(false)}>Stay signed in</Button><Button variant="destructive" onClick={() => { setSignOutOpen(false); void switchFaculty(); }}><LogOut data-icon="inline-start" />Sign out</Button></DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
