import type { Metadata } from "next";
import type { publicPages } from "./public-pages";

export const siteOrigin = new URL(process.env.OFFLINEQR_SITE_URL || "https://offlineqr-editorial.vercel.app");

export const siteDescription = "Capture classroom attendance with rotating QR codes, save scans offline, and reconcile verified records in the faculty workspace.";

export const siteMetadata: Metadata = {
  metadataBase: siteOrigin,
  title: { default: "OfflineQR | Offline Attendance for Institutions", template: "%s | OfflineQR" },
  description: siteDescription,
  icons: { icon: "/branding/offlineqr-mark.svg" },
};

export function publicMetadata(path: "/" | typeof publicPages[number]["path"], title: string, description: string): Metadata {
  const socialTitle = path === "/" ? title : `${title} | OfflineQR`;
  const images = [{ url: "/branding/classroom-hd.webp", alt: "OfflineQR classroom attendance on the student app and faculty workspace" }];
  return {
    title: path === "/" ? { absolute: title } : title,
    description,
    alternates: { canonical: path },
    openGraph: { type: "website", siteName: "OfflineQR", url: path, title: socialTitle, description, images },
    twitter: { card: "summary_large_image", title: socialTitle, description, images },
  };
}
