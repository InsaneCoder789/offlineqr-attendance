import "./globals.css";
import { SiteAnalytics } from "../components/SiteAnalytics";

export { siteMetadata as metadata } from "../lib/public-site";

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return <html lang="en"><body>{children}<SiteAnalytics /></body></html>;
}
