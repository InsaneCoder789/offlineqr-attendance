export const chapters = [
  { title: "A class begins. Everyone connects.", text: "Faculty open an assigned class on the web. A signed classroom QR changes every five seconds. Students open the scanner inside their app.", label: "The classroom", phone: "Today's class", laptop: "Attendance active" },
  { title: "One scan. A signed record.", text: "The registered phone signs the scan for its student. Enrollment, QR expiry and duplicate checks govern acceptance. A device binding is a credential, not a proof of physical proximity.", label: "The scan", phone: "Scan saved", laptop: "Awaiting proof" },
  { title: "The network stops. The record stays.", text: "A durable local outbox keeps the signed proof on the phone. Saved locally does not mean accepted by the server. Retry begins when the service becomes reachable.", label: "Offline continuity", phone: "Waiting to sync", laptop: "Class continues" },
  { title: "Back online. Back in the register.", text: "The server verifies pending proofs and updates the faculty roster. Valid captures can reconcile after session closure within the allowed deadline; rejected proofs remain visible for review.", label: "Reconciliation", phone: "Server accepted", laptop: "Roster updated" },
] as const;

export const mobileChapterText = [
  "Faculty open a class. Students scan its signed QR, which rotates every five seconds.",
  "The registered phone signs the scan. Enrollment, expiry and duplicate checks determine server acceptance, not physical proximity.",
  "The signed proof stays on the phone. It retries when reachable; locally saved is not yet server accepted.",
  "The server verifies queued proofs and updates the roster. Eligible captures can sync after closure; rejections remain visible.",
] as const;

export function chapterAt(progress: number) {
  return Math.min(3, Math.max(0, Math.floor(Math.min(1, Math.max(0, progress)) * 4)));
}

export const plans = [
  { id: "core", name: "Essential", rate: 49, description: "A connected foundation for classroom attendance.", features: ["Student app + faculty workspace", "Signed offline capture and retry", "Device binding + controlled replacement", "Timetables and attendance registers"] },
  { id: "institution", name: "Institution", rate: 79, description: "A tailored deployment for your academic operations.", features: ["Everything in Essential", "Institution branding and configuration", "Academic data onboarding", "Implementation and training package"] },
] as const;

export function annualEstimate(rate: number, students: number) {
  return rate * Math.max(100, Math.min(100000, Math.round(Number.isFinite(students) ? students : 100)));
}
