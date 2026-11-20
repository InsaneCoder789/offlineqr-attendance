import type { Metadata } from "next";
import Link from "next/link";
import { PublicPage } from "../components/marketing/PublicPage";
import styles from "../components/marketing/public-page.module.css";

export const metadata: Metadata = { title: "Page not found", robots: { index: false, follow: false } };

export default function NotFound() {
  return <PublicPage title="Page not found" intro="This address may have changed, or the page may have been removed.">
    <p className={styles.errorCode}>Error 404</p>
    <nav className={styles.actions} aria-label="Recovery links">
      <Link href="/">Go to homepage</Link>
      <Link href="/contact">Get help</Link>
    </nav>
  </PublicPage>;
}
