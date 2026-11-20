import { PublicPage } from "../../components/marketing/PublicPage";
import { publicPages } from "../../lib/public-pages";
import { publicMetadata } from "../../lib/public-site";

const page = publicPages[1];
export const metadata = publicMetadata(page.path, page.title, page.description);

export default function TermsPage() {
  return <PublicPage title="Website terms" intro="Using the public OfflineQR site and planning an institutional deployment.">
    <section><h2>Product information and proposals</h2><p>The public site describes OfflineQR and provides downloadable planning proposals. A generated proposal is an estimate. Deployment scope, pricing, support, and any purchase commitments are established in a separate agreement with the institution.</p></section>
    <section><h2>Institutional access</h2><p>Use the account and workspace assigned to you by your institution. Follow its attendance, device registration, and acceptable-use policies. Keep your credentials private and report incorrect records through your institution’s support channels.</p></section>
    <section><h2>Attendance records</h2><p>A locally saved scan remains pending until verified. Faculty and students should follow their institution’s procedure when a record needs review or correction.</p></section>
  </PublicPage>;
}
