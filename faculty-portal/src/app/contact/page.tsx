import Link from "next/link";
import { PublicPage } from "../../components/marketing/PublicPage";
import { publicPages } from "../../lib/public-pages";
import { publicMetadata } from "../../lib/public-site";

const page = publicPages[2];
export const metadata = publicMetadata(page.path, page.title, page.description);

export default function ContactPage() {
  return <PublicPage title="Contact & support" intro="Find the right place to start for your deployment or attendance question.">
    <section><h2>Planning a deployment</h2><p>Compare plans and <Link href="/#pricing">generate a proposal for your institution</Link>. Include an institutional contact email and the approximate number of students.</p></section>
    <section><h2>Using OfflineQR at your institution</h2><p>Ask your course instructor or attendance office about attendance records. For sign-in, device registration, or phone replacement, contact your institution’s IT team. Include the screen and time of the issue and keep passwords and QR credentials private.</p></section>
  </PublicPage>;
}
