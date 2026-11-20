import type { ReactNode } from "react";
import Link from "next/link";
import { publicPages } from "../../lib/public-pages";
import styles from "./public-page.module.css";

export function PublicLinks() {
  return <nav className={styles.links} aria-label="Website information">{publicPages.map(({ path, title }) => <Link key={path} href={path}>{title}</Link>)}</nav>;
}

export function PublicPage({ title, intro, children }: { title: string; intro: string; children: ReactNode }) {
  return (
    <div className={styles.page}>
      <header className={styles.header}>
        <Link className={styles.brand} href="/">OfflineQR</Link>
        <Link href="/#pricing">Deployment options</Link>
      </header>
      <main className={styles.main}>
        <h1>{title}</h1>
        <p className={styles.intro}>{intro}</p>
        {children}
      </main>
      <footer className={styles.footer}><Link href="/">OfflineQR home</Link><PublicLinks /></footer>
    </div>
  );
}
