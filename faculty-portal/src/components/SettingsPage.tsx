"use client";

import { useEffect, useState } from "react";
import { KeyRound, LogOut, RefreshCw, Save, ShieldCheck, UserRound, Wifi, WifiOff } from "lucide-react";
import { toast } from "sonner";
import { facultyInitials } from "@/lib/format";
import { useFacultyPortal } from "./FacultyPortalProvider";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Field, FieldDescription, FieldGroup, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { PageIntro, StatusBadge } from "./PortalUI";

export function SettingsPage() {
  const { classes, facultyIdentity, online, switchFaculty, updateProfile, changePassword, loading } = useFacultyPortal();
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

  const facts = [
    ["Faculty ID", facultyIdentity?.employee_code ?? facultyIdentity?.id ?? "Unavailable"],
    ["Designation", facultyIdentity?.designation ?? "Pending verification"],
    ["Organizational unit", facultyIdentity?.org_unit ?? "Not assigned"],
    ["Offline readiness", `${classes.filter((course) => course.offline_ready).length} of ${classes.length} classes`],
  ];

  return (
    <>
      <PageIntro
        eyebrow="Account controls"
        title="Profile and security"
        description="Manage faculty contact information, password security, and this browser session."
        actions={<StatusBadge tone={online ? "success" : "warning"} icon={online ? Wifi : WifiOff}>{online ? "Connected" : "Offline mode"}</StatusBadge>}
      />

      <section className="grid gap-5 xl:grid-cols-[minmax(0,0.78fr)_minmax(0,1.22fr)]">
        <Card className="self-start">
          <CardHeader>
            <div className="mb-3 flex size-12 items-center justify-center rounded-lg bg-primary/10 text-lg font-semibold text-primary">{facultyInitials(facultyIdentity)}</div>
            <CardTitle>{facultyIdentity?.display_name ?? "Faculty"}</CardTitle>
            <CardDescription>{facultyIdentity?.institutional_email}</CardDescription>
          </CardHeader>
          <CardContent className="flex flex-col gap-0">
            {facts.map(([label, value]) => (
              <div className="grid gap-1 border-t py-3 first:border-t-0 sm:grid-cols-[9rem_minmax(0,1fr)]" key={label}>
                <span className="text-xs text-muted-foreground">{label}</span>
                <strong className="break-words text-sm font-medium">{value}</strong>
              </div>
            ))}
            <div className="mt-4 border-t pt-4">
              <Button variant="outline" className="w-full" onClick={() => void switchFaculty()}><LogOut data-icon="inline-start" />Sign out of portal</Button>
            </div>
          </CardContent>
        </Card>

        <div className="grid gap-5">
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2"><UserRound className="size-4 text-primary" />Profile details</CardTitle>
              <CardDescription>Keep your faculty directory information current.</CardDescription>
            </CardHeader>
            <CardContent>
              <form onSubmit={(event) => void submitProfile(event)}>
                <FieldGroup>
                  <Field><FieldLabel htmlFor="display-name">Display name</FieldLabel><Input id="display-name" value={displayName} onChange={(event) => setDisplayName(event.target.value)} autoComplete="name" required /></Field>
                  <Field><FieldLabel htmlFor="phone-number">Phone number</FieldLabel><Input id="phone-number" value={phoneNumber} onChange={(event) => setPhoneNumber(event.target.value)} autoComplete="tel" inputMode="tel" placeholder="Optional institutional contact" /></Field>
                  <Button disabled={loading} type="submit" className="w-fit">{loading ? <RefreshCw data-icon="inline-start" className="animate-spin" /> : <Save data-icon="inline-start" />}Save profile</Button>
                </FieldGroup>
              </form>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2"><KeyRound className="size-4 text-primary" />Change password</CardTitle>
              <CardDescription>Use a unique password of at least 14 characters.</CardDescription>
            </CardHeader>
            <CardContent>
              <form onSubmit={(event) => void submitPassword(event)}>
                <FieldGroup>
                  <Field><FieldLabel htmlFor="current-password">Current password</FieldLabel><Input id="current-password" type="password" value={currentPassword} onChange={(event) => setCurrentPassword(event.target.value)} autoComplete="current-password" required /></Field>
                  <Field><FieldLabel htmlFor="new-password">New password</FieldLabel><Input id="new-password" type="password" value={newPassword} onChange={(event) => setNewPassword(event.target.value)} autoComplete="new-password" minLength={14} required /><FieldDescription>Changing your password ends the current faculty session on this browser.</FieldDescription></Field>
                  <Button disabled={loading} type="submit" className="w-fit">{loading ? <RefreshCw data-icon="inline-start" className="animate-spin" /> : <ShieldCheck data-icon="inline-start" />}Update password</Button>
                </FieldGroup>
              </form>
            </CardContent>
          </Card>
        </div>
      </section>
    </>
  );
}
