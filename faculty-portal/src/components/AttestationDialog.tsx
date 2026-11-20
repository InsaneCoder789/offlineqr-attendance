"use client";

import { ClipboardCheck, RefreshCw, ShieldCheck, TriangleAlert } from "lucide-react";
import { usePortalData } from "./FacultyPortalProvider";
import { useAttestationUi, usePortalUiActions } from "./PortalUiState";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Field, FieldDescription, FieldLabel } from "@/components/ui/field";
import { Select, SelectContent, SelectGroup, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";

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
    <Dialog open={Boolean(confirmStudent)} onOpenChange={(open) => { if (!open) setConfirmStudent(null); }}>
      <DialogContent className="sm:max-w-md">
        <span className="mx-auto -mt-1 h-1.5 w-10 rounded-full bg-muted sm:hidden" aria-hidden="true" />
        <DialogHeader>
          <DialogTitle>Faculty attendance attestation</DialogTitle>
          <DialogDescription>
            {confirmStudent ? <>Record <strong className="font-medium text-foreground">{confirmStudent.display_name}</strong> ({confirmStudent.roll_number}) as present.</> : "Record a controlled attendance exception."}
          </DialogDescription>
        </DialogHeader>
        <Field>
          <FieldLabel id="attestation-reason-label">Reason</FieldLabel>
          <Select value={attestationReason} onValueChange={(value) => value && setAttestationReason(value)}>
            <SelectTrigger className="w-full" aria-labelledby="attestation-reason-label"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectGroup>{reasons.map((reason) => <SelectItem key={reason} value={reason}>{reason}</SelectItem>)}</SelectGroup>
            </SelectContent>
          </Select>
          <FieldDescription>Select the factual classroom exception reported by the student.</FieldDescription>
        </Field>
        {error ? (
          <Alert variant="destructive">
            <TriangleAlert />
            <AlertTitle>Attestation not recorded</AlertTitle>
            <AlertDescription>{error}</AlertDescription>
          </Alert>
        ) : null}
        <Alert role="note">
          <ShieldCheck />
          <AlertTitle>Audited faculty action</AlertTitle>
          <AlertDescription>The record includes your faculty identity, timestamp, reason, and the method <strong>FACULTY_ATTESTATION</strong>.</AlertDescription>
        </Alert>
        <DialogFooter className="max-sm:flex-col-reverse max-sm:[&>*]:w-full">
          <Button type="button" variant="outline" onClick={() => setConfirmStudent(null)}>Cancel</Button>
          <Button type="button" disabled={loading || !confirmStudent} aria-busy={loading} onClick={() => void confirmAttestation()}>
            {loading ? <RefreshCw data-icon="inline-start" className="animate-spin" /> : <ClipboardCheck data-icon="inline-start" />}
            {loading ? "Recording" : "Confirm present"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
