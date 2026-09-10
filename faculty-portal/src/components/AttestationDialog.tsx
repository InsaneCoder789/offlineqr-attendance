"use client";

import { ClipboardCheck, RefreshCw, ShieldCheck } from "lucide-react";
import { useFacultyPortal } from "./FacultyPortalProvider";
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
  const { attestationReason, confirmAttestation, confirmStudent, loading, setAttestationReason, setConfirmStudent } = useFacultyPortal();

  return (
    <Dialog open={Boolean(confirmStudent)} onOpenChange={(open) => { if (!open) setConfirmStudent(null); }}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Faculty attendance attestation</DialogTitle>
          <DialogDescription>
            {confirmStudent ? <>Record <strong className="font-medium text-foreground">{confirmStudent.display_name}</strong> ({confirmStudent.roll_number}) as present.</> : "Record a controlled attendance exception."}
          </DialogDescription>
        </DialogHeader>
        <Field>
          <FieldLabel>Reason</FieldLabel>
          <Select value={attestationReason} onValueChange={(value) => value && setAttestationReason(value)}>
            <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectGroup>{reasons.map((reason) => <SelectItem key={reason} value={reason}>{reason}</SelectItem>)}</SelectGroup>
            </SelectContent>
          </Select>
          <FieldDescription>Select the factual classroom exception reported by the student.</FieldDescription>
        </Field>
        <Alert>
          <ShieldCheck />
          <AlertTitle>Audited faculty action</AlertTitle>
          <AlertDescription>The record includes your faculty identity, timestamp, reason, and the method <strong>FACULTY_ATTESTATION</strong>.</AlertDescription>
        </Alert>
        <DialogFooter>
          <Button variant="outline" onClick={() => setConfirmStudent(null)}>Cancel</Button>
          <Button disabled={loading || !confirmStudent} onClick={() => void confirmAttestation()}>
            {loading ? <RefreshCw data-icon="inline-start" className="animate-spin" /> : <ClipboardCheck data-icon="inline-start" />}
            {loading ? "Recording" : "Confirm present"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
