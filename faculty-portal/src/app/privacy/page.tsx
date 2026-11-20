import Link from "next/link";
import { PublicPage } from "../../components/marketing/PublicPage";
import { publicPages } from "../../lib/public-pages";
import { publicMetadata } from "../../lib/public-site";

const page = publicPages[0];
export const metadata = publicMetadata(page.path, page.title, page.description);

export default function PrivacyPage() {
  return <PublicPage title="Privacy" intro="How information is used on the OfflineQR website and in an institution’s attendance workspace.">
    <section><h2>Proposals</h2><p>The proposal form sends institution and contact details, deployment choices, and any notes you enter to generate a PDF. The form returns the document to your browser. Keep student records, passwords, and payment information out of the notes field.</p></section>
    <section><h2>Website analytics</h2><p>The public editorial deployment uses Vercel Web Analytics for page views. The analytics configuration removes query strings and fragments from recorded URLs. The hosted site and proposal endpoint receive technical information needed to serve requests and apply rate limits.</p></section>
    <section><h2>Attendance and device records</h2><p>An institution’s deployment can process account identifiers, course enrollment, attendance proofs, and device registration and replacement history. The app can hold attendance proofs locally while offline. The workspace uses browser storage for session continuity and preferences. Institution-specific access, retention, and handling should be described by your institution.</p></section>
    <section><h2>Questions about a record</h2><p>Contact your institution’s attendance office or IT team about access, corrections, or the handling of student and faculty records. See <Link href="/contact">Contact &amp; support</Link> for the appropriate route.</p></section>
  </PublicPage>;
}
