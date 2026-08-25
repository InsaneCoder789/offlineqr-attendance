"use client";

import { useFacultyPortal } from "./FacultyPortalProvider";
import { Icon } from "./Icons";

const reasons = [
  "Student device failure",
  "QR scanning failure",
  "Local connectivity failure",
  "Device registration problem",
  "System error",
  "Other approved reason",
];

export function AttestationDialog() {
  const {
    attestationReason,
    confirmAttestation,
    confirmStudent,
    loading,
    setAttestationReason,
    setConfirmStudent,
  } = useFacultyPortal();

  if (!confirmStudent) return null;

  return (
    <div className="dialog-backdrop" role="presentation" onClick={(event) => {
      if (event.currentTarget === event.target) setConfirmStudent(null);
    }}>
      <section className="dialog" role="dialog" aria-modal="true" aria-labelledby="confirmTitle">
        <p className="eyeline">Faculty attestation</p>
        <h2 id="confirmTitle">Mark attendance manually</h2>
        <p>Mark <strong>{confirmStudent.display_name}</strong> ({confirmStudent.roll_number}) as <strong>Present</strong> for this session?</p>
        <label className="dialog-field">
          <span>Attestation reason</span>
          <select value={attestationReason} onChange={(event) => setAttestationReason(event.target.value)}>
            {reasons.map((reason) => <option key={reason} value={reason}>{reason}</option>)}
          </select>
        </label>
        <div className="attestation-audit">
          <Icon name="check" />
          <span>Recorded as <strong>FACULTY_ATTESTATION</strong> with faculty identity, timestamp, reason, and audit trail.</span>
        </div>
        <div className="dialog-actions">
          <button className="secondary" onClick={() => setConfirmStudent(null)}>Cancel</button>
          <button disabled={loading} onClick={() => void confirmAttestation()}>
            <Icon name="check" />
            {loading ? "Recording..." : "Confirm Present"}
          </button>
        </div>
      </section>
    </div>
  );
}
