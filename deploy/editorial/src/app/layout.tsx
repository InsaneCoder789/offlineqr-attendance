import type { Metadata } from "next";
import "./globals.css";
import { SiteAnalytics } from "../components/SiteAnalytics";

export const metadata: Metadata = {
  title: "OfflineQR | Attendance, beyond the connection",
  description: "Dynamic QR attendance for institutions. Discover the student app, faculty workspace and offline attendance workflow.",
  icons: { icon: "/branding/offlineqr-mark.svg" },
  robots: { index: true, follow: true },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return <html lang="en"><body>{children}<SiteAnalytics /></body></html>;
}
