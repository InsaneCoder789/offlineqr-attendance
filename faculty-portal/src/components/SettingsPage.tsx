"use client";

import { useEffect, useState } from "react";
import { Eye, EyeOff, KeyRound, LogOut, RefreshCw, Save, ShieldCheck, UserRound, Wifi, WifiOff } from "lucide-react";
import { toast } from "sonner";
import { facultyInitials } from "@/lib/format";
import { usePortalData } from "./FacultyPortalProvider";
import { Button } from "@/components/ui/button";
import { Field, FieldDescription, FieldGroup, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { ErrorPanel, LoadingPanel, PageIntro, StatusBadge } from "./PortalUI";

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

export function SettingsPage() {
  const { classes, facultyIdentity, online, switchFaculty, updateProfile, changePassword, loading, passwordChangeRequired, error, refresh } = usePortalData();
  const [showNew, setShowNew] = useState(false);
  const [displayName, setDisplayName] = useState(facultyIdentity?.display_name ?? "");
  const [phoneNumber, setPhoneNumber] = useState(facultyIdentity?.phone_number ?? "");
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");

  useEffect(() => {
    setDisplayName(facultyIdentity?.display_name ?? "");
    setPhoneNumber(facultyIdentity?.phone_number ?? "");
  }, [facultyIdentity]);

  async function submitProfile(event: React.FormEvent) {
    event.preventDefault();
    try {
      await updateProfile(displayName, phoneNumber || null);
      toast.success("Faculty profile updated");
    } catch { /* Provider exposes the service error in the shell. */ }
  }

  async function submitPassword(event: React.FormEvent) {
    event.preventDefault();
    try {
      await changePassword(currentPassword, newPassword);
      setCurrentPassword("");
      setNewPassword("");
      toast.success("Password updated. Sign in again to continue.");
    } catch { /* Provider exposes the service error in the shell. */ }
  }

  const strength = passwordStrength(newPassword);

  const facts = [
    ["Faculty ID", facultyIdentity?.employee_code ?? facultyIdentity?.id ?? "Unavailable"],
    ["Designation", facultyIdentity?.designation ?? "Pending verification"],
    ["Organizational unit", facultyIdentity?.org_unit ?? "Not assigned"],
    ["Offline readiness", `${classes.filter((course) => course.offline_ready).length} of ${classes.length} classes`],
  ];

  if (!facultyIdentity && loading) return <LoadingPanel rows={5} label="Loading profile" className="dashboard-canvas rounded-xl bg-card" />;
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

      <section className="dashboard-canvas grid overflow-hidden rounded-xl bg-card xl:grid-cols-[minmax(18rem,0.72fr)_minmax(0,1.28fr)]">
        <aside className="self-stretch bg-muted/35 p-5 sm:p-7">
          <header>
            <div className="mb-3 flex size-12 items-center justify-center rounded-lg bg-primary/10 text-lg font-semibold text-primary">{facultyInitials(facultyIdentity)}</div>
            <h2 className="text-xl font-semibold">{facultyIdentity?.display_name ?? "Faculty"}</h2>
            <p className="mt-1 text-sm text-muted-foreground">{facultyIdentity?.institutional_email}</p>
          </header>
          <div className="mt-6 flex flex-col gap-0">
            {facts.map(([label, value]) => (
              <div className="grid gap-1 border-t py-3 first:border-t-0 sm:grid-cols-[9rem_minmax(0,1fr)]" key={label}>
                <span className="text-xs text-muted-foreground">{label}</span>
                <strong className="break-words text-sm font-medium">{value}</strong>
              </div>
            ))}

          </div>
        </aside>

        <div className="divide-y divide-border/60">
          <section className="p-5 sm:p-7">
            <header>
              <h2 className="flex items-center gap-2 text-lg font-semibold"><UserRound className="size-4 text-primary" />Profile details</h2>
              <p className="mt-1 text-sm text-muted-foreground">Keep your faculty directory information current.</p>
            </header>
            <div className="mt-6">
              <form onSubmit={(event) => void submitProfile(event)}>
                <FieldGroup>
                  <Field><FieldLabel htmlFor="display-name">Display name</FieldLabel><Input id="display-name" value={displayName} onChange={(event) => setDisplayName(event.target.value)} autoComplete="name" required /></Field>
                  <Field><FieldLabel htmlFor="phone-number">Phone number</FieldLabel><Input id="phone-number" value={phoneNumber} onChange={(event) => setPhoneNumber(event.target.value)} autoComplete="tel" inputMode="tel" placeholder="Optional institutional contact" /></Field>
                  <Button disabled={loading} type="submit" className="w-fit max-sm:w-full">{loading ? <RefreshCw data-icon="inline-start" className="animate-spin" /> : <Save data-icon="inline-start" />}Save profile</Button>
                </FieldGroup>
              </form>
            </div>
          </section>

          <section className="p-5 sm:p-7">
            <header>
              <h2 className="flex items-center gap-2 text-lg font-semibold"><KeyRound className="size-4 text-primary" />Change password</h2>
              <p className="mt-1 text-sm text-muted-foreground">Use a unique password of at least 14 characters.</p>
            </header>
            <div className="mt-6">
              <form onSubmit={(event) => void submitPassword(event)}>
                <FieldGroup>
                  <Field><FieldLabel htmlFor="current-password">Current password</FieldLabel><Input id="current-password" type="password" value={currentPassword} onChange={(event) => setCurrentPassword(event.target.value)} autoComplete="current-password" autoFocus={passwordChangeRequired} required /></Field>
                  <Field><FieldLabel htmlFor="new-password">New password</FieldLabel><Input id="new-password" type={showNew ? "text" : "password"} value={newPassword} onChange={(event) => setNewPassword(event.target.value)} autoComplete="new-password" minLength={14} required /><button type="button" className="inline-flex min-h-11 w-fit items-center gap-2 text-xs font-medium text-muted-foreground underline-offset-4 hover:underline" aria-pressed={showNew} onClick={() => setShowNew((v) => !v)}>{showNew ? <EyeOff className="size-4" /> : <Eye className="size-4" />}{showNew ? "Hide" : "Show"} new password</button>
                    <div role="status" aria-live="polite">
                      <div className="h-1.5 overflow-hidden rounded-full bg-muted" aria-hidden="true"><div className={`h-full rounded-full transition-[width] ${strength.color}`} style={{ width: `${strength.score * 25}%` }} /></div>
                      <p className="mt-1 text-xs text-muted-foreground">{newPassword ? `Strength: ${strength.label}` : "Use 14 or more characters with a mix of letters, numbers and symbols."}</p>
                    </div>
                    <FieldDescription>Changing your password ends the current faculty session on this browser.</FieldDescription></Field>
                  <Button disabled={loading} type="submit" className="w-fit max-sm:w-full">{loading ? <RefreshCw data-icon="inline-start" className="animate-spin" /> : <ShieldCheck data-icon="inline-start" />}Update password</Button>
                </FieldGroup>
              </form>
            </div>
          </section>

          <section className="p-5 sm:p-7" aria-labelledby="danger-zone">
            <h2 id="danger-zone" className="flex items-center gap-2 text-lg font-semibold text-destructive"><LogOut className="size-4" />Danger zone</h2>
            <p className="mt-1 text-sm text-muted-foreground">Signing out removes this faculty session from this browser. Unsynced offline work stays on the device.</p>
            <Button variant="destructive" className="mt-4 max-sm:w-full" onClick={() => void switchFaculty()}><LogOut data-icon="inline-start" />Sign out of portal</Button>
          </section>
        </div>
      </section>
    </>
  );
}
