import type { Metadata } from "next";
import "../styles.css";
import { FacultyPortalProvider } from "../components/FacultyPortalProvider";
import { FacultyPortalShell } from "../components/FacultyPortalShell";
import { OfflineRuntime } from "../components/OfflineRuntime";

export const metadata: Metadata = {
  title: "KIIT Faculty Attendance Portal",
  description: "Offline-first dynamic QR attendance console for KIIT faculty.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>
        <OfflineRuntime />
        <FacultyPortalProvider>
          <FacultyPortalShell>{children}</FacultyPortalShell>
        </FacultyPortalProvider>
      </body>
    </html>
  );
}
