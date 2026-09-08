"use client";

import { useEffect, useState } from "react";
import { facultyInitials } from "../lib/format";
import { useFacultyPortal } from "./FacultyPortalProvider";
import { Icon } from "./Icons";

export function SettingsPage() {
  const { classes, facultyIdentity, online, switchFaculty, updateProfile, changePassword, loading } = useFacultyPortal();
  const [displayName, setDisplayName] = useState(facultyIdentity?.display_name ?? "");
  const [phoneNumber, setPhoneNumber] = useState(facultyIdentity?.phone_number ?? "");
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [message, setMessage] = useState<string | null>(null);

  useEffect(() => {
    setDisplayName(facultyIdentity?.display_name ?? "");
    setPhoneNumber(facultyIdentity?.phone_number ?? "");
  }, [facultyIdentity]);

  async function submitProfile(event: React.FormEvent) {
    event.preventDefault();
    await updateProfile(displayName, phoneNumber || null);
    setMessage("Profile updated.");
  }

  async function submitPassword(event: React.FormEvent) {
    event.preventDefault();
    await changePassword(currentPassword, newPassword);
    setCurrentPassword("");
    setNewPassword("");
    setMessage("Password updated.");
  }

  return (
    <section className="panel settings">
      <div className="section-head">
        <div>
          <h2>Faculty Profile</h2>
          <p>Account details and portal status.</p>
        </div>
      </div>
      <div className="setting-row">
        <span>Account</span>
        <strong>{facultyIdentity?.display_name ?? "Faculty"}</strong>
      </div>
      <div className="setting-row">
        <span>Faculty ID</span>
        <strong>{facultyIdentity?.employee_code ?? facultyIdentity?.id ?? "Unavailable"}</strong>
      </div>
      <div className="setting-row">
        <span>Faculty initials</span>
        <strong>{facultyInitials(facultyIdentity)}</strong>
      </div>
      <div className="setting-row">
        <span>Role</span>
        <strong>{facultyIdentity?.designation ?? "Role pending verification"}</strong>
      </div>
      <div className="setting-row">
        <span>Organizational unit</span>
        <strong>{facultyIdentity?.org_unit ?? "Not assigned"}</strong>
      </div>
      <div className="setting-row">
        <span>Synchronization</span>
        <strong className="inline-status">
          <Icon name={online ? "wifiOn" : "wifiOff"} />
          {online ? "Online" : "Offline Mode"}
        </strong>
      </div>
      <div className="setting-row">
        <span>Offline-ready classes</span>
        <strong>{classes.filter((course) => course.offline_ready).length} of {classes.length} ready</strong>
      </div>
      <div className="setting-row">
        <span>Portal type</span>
        <strong>Secure faculty console</strong>
      </div>
      <div className="setting-row">
        <span>Attendance mode</span>
        <strong>Dynamic QR with manual attestation</strong>
      </div>
      <form className="profile-form" onSubmit={(event) => void submitProfile(event)}>
        <h3>Profile details</h3>
        <label className="login-field">
          <span>Display name</span>
          <input value={displayName} onChange={(event) => setDisplayName(event.target.value)} autoComplete="name" required />
        </label>
        <label className="login-field">
          <span>Phone number</span>
          <input value={phoneNumber} onChange={(event) => setPhoneNumber(event.target.value)} autoComplete="tel" inputMode="tel" />
        </label>
        <button disabled={loading} type="submit"><Icon name="check" />Save profile</button>
      </form>
      <form className="profile-form" onSubmit={(event) => void submitPassword(event)}>
        <h3>Change password</h3>
        <label className="login-field">
          <span>Current password</span>
          <input type="password" value={currentPassword} onChange={(event) => setCurrentPassword(event.target.value)} autoComplete="current-password" required />
        </label>
        <label className="login-field">
          <span>New password</span>
          <input type="password" value={newPassword} onChange={(event) => setNewPassword(event.target.value)} autoComplete="new-password" minLength={14} required />
        </label>
        <button disabled={loading} type="submit"><Icon name="check" />Update password</button>
      </form>
      {message ? <p className="notice success">{message}</p> : null}
      <button className="secondary" onClick={() => void switchFaculty()}>
        <Icon name="settings" />
        Sign out of this portal
      </button>
    </section>
  );
}
