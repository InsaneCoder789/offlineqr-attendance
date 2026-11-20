export const chapters = [
  { title: "Open the classroom QR.", text: "Faculty select an assigned class and display the signed QR. The code rotates every five seconds.", label: "Classroom" },
  { title: "Scan from the student app.", text: "The registered phone signs a proof for this student and session. The app shows the result of the capture.", label: "Scan" },
  { title: "Keep the scan when Wi-Fi drops.", text: "The phone saves the proof locally and retries when it reaches the service. The app shows it as pending until verification.", label: "Offline" },
  { title: "Update the faculty register.", text: "When the connection returns, the server verifies the proof and updates the roster. Rejected proofs remain visible for review.", label: "Verify" },
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
