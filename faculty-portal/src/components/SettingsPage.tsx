"use client";

import { facultyInitials } from "../lib/format";
import { useFacultyPortal } from "./FacultyPortalProvider";
import { Icon } from "./Icons";

export function SettingsPage() {
  const { classes, facultyIdentity, online, switchFaculty } = useFacultyPortal();

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
        <strong>Next.js PWA-ready console</strong>
      </div>
      <div className="setting-row">
        <span>Attendance mode</span>
        <strong>Dynamic QR with manual attestation</strong>
      </div>
      <div className="setting-row">
        <span>Backend</span>
        <strong>http://127.0.0.1:8000</strong>
      </div>
      <button className="secondary" onClick={switchFaculty}>
        <Icon name="settings" />
        Switch faculty account
      </button>
    </section>
  );
}
