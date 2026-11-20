"use client";

import { ClipboardCheck, RefreshCw, ShieldCheck, TriangleAlert } from "lucide-react";
import { usePortalData } from "./FacultyPortalProvider";
import { useAttestationUi, usePortalUiActions } from "./PortalUiState";
import { initials } from "./LiveWidgets";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import styles from "./ops.module.css";
import { Button } from "./ui/button";

const reasons = [
  "Student device failure",
  "QR scanning failure",
  "Local connectivity failure",
  "Device registration problem",
  "System error",
  "Other approved reason",
];

export function AttestationDialog() {
  const { confirmAttestation, loading, error } = usePortalData();
  const { attestationReason, confirmStudent } = useAttestationUi();
  const { setAttestationReason, setConfirmStudent } = usePortalUiActions();

  return (
    <Dialog open={Boolean(confirmStudent)} onOpenChange={(open) => { if (!open && !loading) setConfirmStudent(null); }}>
      <DialogContent className={`${styles.scope} max-h-[92dvh] overflow-y-auto sm:max-w-md`}>
        <span className="mx-auto -mt-1 h-1.5 w-10 rounded-full bg-muted sm:hidden" aria-hidden="true" />
        <DialogHeader>
          <DialogTitle>Faculty attestation</DialogTitle>
          <DialogDescription>Record a controlled attendance exception for this student.</DialogDescription>
        </DialogHeader>
        {confirmStudent ? (
          <div className={styles.attHead}>
            <span className={`${styles.avatar} ${styles.attAvatar}`} aria-hidden="true">{initials(confirmStudent.display_name)}</span>
            <div style={{ minWidth: 0 }}>
              <strong className={styles.nameCol} style={{ display: "block" }}>{confirmStudent.display_name}</strong>
              <span className={styles.mono} style={{ color: "var(--muted-foreground)" }}>{confirmStudent.roll_number}</span>
            </div>
          </div>
        ) : null}
        <fieldset className={styles.reasons}>
          <legend className={styles.fieldLabel} style={{ marginBottom: "0.5rem" }}>Reason</legend>
          {reasons.map((reason) => (
            <label key={reason} className={styles.reasonOption}>
              <input type="radio" name="attestation-reason" value={reason} checked={attestationReason === reason} onChange={() => setAttestationReason(reason)} />
              <span>{reason}</span>
            </label>
          ))}
        </fieldset>
        {error ? (
          <div className={styles.attError} role="alert">
            <TriangleAlert aria-hidden="true" />
            <div><strong style={{ display: "block" }}>Attestation not recorded</strong><span>{error}</span></div>
          </div>
        ) : null}
        <p className={styles.attNote} role="note">
          <ShieldCheck aria-hidden="true" />
          <span>Audited action. The record includes your faculty identity, timestamp, reason and the method FACULTY_ATTESTATION.</span>
        </p>
        <div className={styles.attFooter}>
          <Button variant="outline" disabled={loading} onClick={() => setConfirmStudent(null)}>Cancel</Button>
          <Button disabled={loading || !confirmStudent || !attestationReason} aria-busy={loading} onClick={() => void confirmAttestation()}>
            {loading ? <RefreshCw className={styles.spin} aria-hidden="true" /> : <ClipboardCheck aria-hidden="true" />}
            {loading ? "Recording" : "Confirm present"}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
