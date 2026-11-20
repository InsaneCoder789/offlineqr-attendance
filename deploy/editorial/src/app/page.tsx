import { ScrollEditorial } from "../components/marketing/ScrollEditorial";
import { publicMetadata, siteDescription } from "../lib/public-site";

export const metadata = publicMetadata("/", "OfflineQR | Offline Attendance for Institutions", siteDescription);

export default function HomePage() {
  return <ScrollEditorial publicOnly />;
}
