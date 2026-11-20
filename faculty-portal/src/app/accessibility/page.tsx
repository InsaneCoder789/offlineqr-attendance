import Link from "next/link";
import { PublicPage } from "../../components/marketing/PublicPage";
import { publicPages } from "../../lib/public-pages";
import { publicMetadata } from "../../lib/public-site";

const page = publicPages[3];
export const metadata = publicMetadata(page.path, page.title, page.description);

export default function AccessibilityPage() {
  return <PublicPage title="Accessibility" intro="Ways to navigate the website and request help with attendance.">
    <section><h2>Navigation and motion</h2><p>Use Tab to reach navigation links and controls. The homepage offers a skip link for the animated story. The story uses your device’s reduced-motion preference for its transitions.</p></section>
    <section><h2>Classroom access</h2><p>If you cannot use the scanner or read a classroom QR, tell your instructor. Your institution can explain its process for recording attendance in those cases.</p></section>
    <section><h2>Report a barrier</h2><p>Tell your support team which screen or action was difficult and what device or assistive technology you were using. See <Link href="/contact">Contact &amp; support</Link>.</p></section>
  </PublicPage>;
}
