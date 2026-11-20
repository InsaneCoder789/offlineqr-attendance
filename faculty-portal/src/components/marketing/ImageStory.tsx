"use client";

import Image from "next/image";
import { Check, Clock3, QrCode, ScanLine, WifiOff } from "lucide-react";
import styles from "./image-story.module.css";

const screens = [
  { id: "classroom", phone: "Today’s class", detail: "Computer Networks", action: "Open scanner", icon: QrCode, roster: "Attendance open", present: 0 },
  { id: "scan", phone: "Scan captured", detail: "Proof signed on this phone", action: "View attendance", icon: ScanLine, roster: "Awaiting verification", present: 0 },
  { id: "offline", phone: "Saved offline", detail: "Sync when connected", action: "View pending scan", icon: WifiOff, roster: "Proof pending sync", present: 0 },
  { id: "reconcile", phone: "Attendance verified", detail: "Server accepted", action: "Done", icon: Check, roster: "Roster updated", present: 3 },
] as const;

export function ImageStory({ chapter }: { chapter: number }) {
  const screen = screens[chapter] ?? screens[0];
  const Icon = screen.icon;
  const PortalStatus = screen.present ? Check : Clock3;

  return (
    <div className={styles.scene} data-story-frame={screen.id} role="img" aria-label={`Illustrative workflow. Student app: ${screen.phone}. Faculty workspace: ${screen.roster}.`}>
      <Image src="/branding/devices-hd.webp" alt="" fill sizes="(max-width: 760px) 100vw, (max-width: 1440px) 65vw, 1000px" />
      <div className={styles.phone} aria-hidden="true">
        <div key={screen.id} className={styles.phoneContent}>
          <b className={styles.wordmark}>OfflineQR</b>
          <div className={styles.phoneIcon}><Icon /></div>
          <strong>{screen.phone}</strong>
          <small>{screen.detail}</small>
          <span>{screen.action}</span>
        </div>
      </div>
      <div className={styles.laptop} aria-hidden="true">
        <header className={styles.portalHeader}><b>OfflineQR</b><span>Faculty workspace</span></header>
        <div className={styles.portalMain} key={screen.id}>
          <div className={styles.portalHeading}>
            <div><small>Section A</small><strong>Computer Networks</strong></div>
            <span><PortalStatus />{screen.roster}</span>
          </div>
          <div className={styles.portalGrid}>
            <div className={styles.qrCard}><QrCode /><span>Classroom QR</span></div>
            <div className={styles.roster}>
              <b>{screen.present} of 3 present</b>
              {["Student 01", "Student 02", "Student 03"].map((name) => (
                <div key={name}><span>{name}</span><span>{screen.present ? "Present" : "Awaiting scan"}</span></div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
