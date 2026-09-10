import type { Metadata } from "next";
import "./globals.css";
import { FacultyPortalProvider } from "../components/FacultyPortalProvider";
import { FacultyPortalShell } from "../components/FacultyPortalShell";
import { OfflineRuntime } from "../components/OfflineRuntime";
import { GeistSans } from "geist/font/sans";
import { TooltipProvider } from "@/components/ui/tooltip";
import { Toaster } from "@/components/ui/sonner";

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
    <html lang="en" className={GeistSans.variable}>
      <body>
        <OfflineRuntime />
        <TooltipProvider>
          <FacultyPortalProvider>
            <FacultyPortalShell>{children}</FacultyPortalShell>
          </FacultyPortalProvider>
          <Toaster position="top-right" richColors />
        </TooltipProvider>
      </body>
    </html>
  );
}
