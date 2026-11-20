import type { Metadata } from "next";
import "./globals.css";
import { GeistSans } from "geist/font/sans";
import { TooltipProvider } from "@/components/ui/tooltip";
import { Toaster } from "@/components/ui/sonner";
import { ProductCacheMigration } from "@/components/ProductCacheMigration";

export const metadata: Metadata = {
  title: { default: "OfflineQR | Attendance, beyond the connection", template: "%s | OfflineQR" },
  description: "Dynamic QR attendance for institutions. A student app, faculty workspace and device governance console, configured around your institution.",
  icons: { icon: "/branding/offlineqr-mark.svg" },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className={GeistSans.variable}>
      <body>
        <ProductCacheMigration />
        <TooltipProvider>
          {children}
          <Toaster position="top-right" richColors />
        </TooltipProvider>
      </body>
    </html>
  );
}
