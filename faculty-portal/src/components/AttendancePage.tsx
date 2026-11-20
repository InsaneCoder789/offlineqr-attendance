"use client";

import { useRouter } from "next/navigation";
import { ArrowLeft, CheckCircle2, Radio, Search } from "lucide-react";
import { presentCount } from "@/lib/format";
import { usePortalData } from "./FacultyPortalProvider";
import { usePortalUiActions, useRosterFilters } from "./PortalUiState";
import { QrPanel } from "./QrPanel";
import { RosterTable } from "./RosterTable";
import { StatePanel } from "./StatePanel";
import { PageIntro } from "./PortalUI";
import { useState } from "react";
import styles from "./ops.module.css";
import live from "./attendance.module.css";
import { Button } from "./ui/button";

export type RosterView = "all" | "present" | "pending" | "attested";

export function AttendancePage() {
  const router = useRouter();
  const { roster, session, error, loading } = usePortalData();

  if (!session) {
    return (
      <div className={styles.scope}>
        <PageIntro eyebrow="Classroom operations" title="Live attendance" description="Open a scheduled class to begin a signed dynamic QR session." />
        {loading ? <div className={`${styles.skel}`} style={{ height: "18rem" }} role="status" aria-busy="true"><span className="sr-only">Loading session</span></div> : (
          <StatePanel
            icon={Radio}
            title={error ? "Could not check for an active session" : "No active attendance session"}
            text="Choose a class from your teaching schedule, then start attendance when the classroom is ready."
            action={<Button onClick={() => router.push("/classes")}><ArrowLeft aria-hidden="true" />Open classes</Button>}
          />
        )}
      </div>
    );
  }

  if (session.closed_at) {
    return (
      <div className={styles.scope}>
        <PageIntro eyebrow="Classroom operations" title={`${session.course_code} · ${session.section_code}`} description={session.course_name} />
        <StatePanel
          icon={CheckCircle2}
          title={session.offline_pending_activation ? "Session ended on this device" : "Session closed"}
          text={session.offline_pending_activation ? "Session closure is saved on this device for reconciliation." : roster.length ? `${presentCount(roster)} of ${roster.length} marked present in the available roster. Check Records for the latest count.` : "Open Records to review attendance."}
          action={<div className={styles.cta} style={{ justifyContent: "center" }}><Button onClick={() => router.push("/records")}>View records</Button><Button variant="outline" onClick={() => router.push("/classes")}>Back to classes</Button></div>}
        />
      </div>
    );
  }

  return <LiveSession key={session.id} />;
}

function LiveSession() {
  const { roster, session } = usePortalData();
  const [attested, setAttested] = useState(false);
  if (!session) return null;
  const present = presentCount(roster);
  return (
    <div className={live.room}>
      <header className={`silk-heading ${live.masthead}`}>
        <div>
          <p className={live.kicker}>{session.offline_pending_activation ? "Offline session" : "Session open"} · {session.course_code} · {session.section_code}</p>
          <h2>{session.course_name}</h2>
          <p className={live.meta}>{session.room ? `Room ${session.room}` : "Room not assigned"}</p>
        </div>
        {roster.length > 0 && (
          <div className={live.tally}>
            <strong>{present}<span> / {roster.length}</span></strong>
            <p>Students present</p>
            <progress value={present} max={roster.length} aria-label="Students present" />
          </div>
        )}
      </header>
      <div className={live.workspace}>
        <QrPanel />
        <section className={live.register} aria-label="Student roster">
          <RosterControls attested={attested} setAttested={setAttested} />
          <RosterTable attestedOnly={attested} />
        </section>
      </div>
    </div>
  );
}

function RosterControls({ attested, setAttested }: { attested: boolean; setAttested: (value: boolean) => void }) {
  const { roster } = usePortalData();
  const { rosterFilter, rosterQuery } = useRosterFilters();
  const { setRosterFilter, setRosterQuery } = usePortalUiActions();
  const present = presentCount(roster);
  const attestedCount = roster.filter((student) => student.attendance_method === "FACULTY_ATTESTATION" && student.attendance_status === "PRESENT").length;
  const chips: Array<{ id: RosterView; label: string; count: number }> = [
    { id: "all", label: "All", count: roster.length },
    { id: "present", label: "Present", count: present },
    { id: "pending", label: "Not recorded", count: roster.length - present },
    { id: "attested", label: "Attested", count: attestedCount },
  ];
  const current: RosterView = attested ? "attested" : rosterFilter;
  return (
    <>
      <div className={styles.rosterHead}>
        <h3 className={styles.rosterTitle}>Student roster</h3>

      </div>
      <div className={`${styles.rosterTools} ${live.rosterTools}`}>
        <label className={styles.search}>
          <Search aria-hidden="true" />
          <input type="search" className={styles.searchInput} value={rosterQuery} placeholder="Name or roll number" aria-label="Search roster by roll number or name" onChange={(event) => setRosterQuery(event.target.value)} />
        </label>
        <div className={styles.chips} role="group" aria-label="Roster filter">
          {chips.map((chip) => (
            <button key={chip.id} type="button" className={styles.chip} aria-pressed={current === chip.id} onClick={() => {
              if (chip.id === "attested") { setAttested(true); setRosterFilter("present"); } else { setAttested(false); setRosterFilter(chip.id); }
            }}>
              {chip.label}{roster.length > 0 && <span className={styles.chipCount}>{chip.count}</span>}
            </button>
          ))}
        </div>
      </div>
    </>
  );
}
