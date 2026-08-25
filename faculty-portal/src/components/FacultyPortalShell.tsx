"use client";

import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { facultyInitials, titleFor, dateLabel } from "../lib/format";
import { useFacultyPortal } from "./FacultyPortalProvider";
import { Icon } from "./Icons";
import { LoginPage } from "./LoginPage";
import { QrPanel } from "./QrPanel";
import { AttestationDialog } from "./AttestationDialog";

const navItems = [
  { href: "/dashboard", label: "Dashboard", icon: "dashboard" },
  { href: "/classes", label: "My Classes", icon: "classes" },
  { href: "/attendance", label: "Attendance", icon: "attendance" },
  { href: "/records", label: "Records", icon: "records" },
  { href: "/settings", label: "Settings", icon: "settings" },
] as const;

export function FacultyPortalShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const { facultyIdentity, online, loading, error, refresh, projectorMode, session, confirmStudent } = useFacultyPortal();
  const initials = facultyInitials(facultyIdentity);

  if (!facultyIdentity) return <LoginPage />;
  if (projectorMode && session) return <QrPanel projector />;

  return (
    <>
      <div className="app-shell">
        <aside className="sidebar">
          <div className="brand-wrapper">
            <Image src="/branding/kiit_logo.png" alt="KIIT University" className="brand" width={118} height={118} priority />
            <span className="brand-subtitle">Faculty Portal</span>
          </div>
          <nav>
            {navItems.map((item) => {
              const active = pathname === item.href || (item.href !== "/dashboard" && pathname.startsWith(item.href));
              return (
                <Link key={item.href} className={`nav ${active ? "active" : ""}`} href={item.href} aria-current={active ? "page" : undefined}>
                  <Icon name={item.icon} />
                  {item.label}
                </Link>
              );
            })}
          </nav>
          <div className="sidebar-footer">
            <div className="faculty-mini">
              <div className="avatar compact" aria-hidden="true">{initials}</div>
              <div>
                <strong>{facultyIdentity.display_name}</strong>
                <span>{online ? "Connected" : "Offline ready"}</span>
              </div>
            </div>
          </div>
        </aside>
        <main className="content">
          <header className="topbar">
            <div>
              <p className="eyeline">{dateLabel(new Date())}</p>
              <h1>{titleFor(pathname)}</h1>
            </div>
            <div className="top-actions">
              <span className={`status with-icon ${online ? "success" : "warning"}`} title={online ? "Connected to server" : "Working offline"}>
                <Icon name={online ? "wifiOn" : "wifiOff"} />
                {online ? "Synced" : "Offline"}
              </span>
              <button className="secondary" disabled={loading} aria-label="Sync data" onClick={() => void refresh()}>
                <Icon name="refresh" />
                {loading ? "Syncing..." : "Sync"}
              </button>
              <div className="avatar" aria-label="Faculty profile" title={`Logged in as ${facultyIdentity.display_name}`}>{initials}</div>
            </div>
          </header>
          {error ? (
            <div className="notice error" role="alert">
              <Icon name="alert" />
              <span>{error}. Showing saved data where available.</span>
            </div>
          ) : null}
          {children}
        </main>
      </div>
      {confirmStudent ? <AttestationDialog /> : null}
    </>
  );
}
