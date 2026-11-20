"use client";

import Link from "next/link";
import "@fontsource-variable/manrope";
import "@fontsource-variable/dm-sans";
import { useEffect, useRef, useState } from "react";
import { ArrowDown, ArrowRight, Fingerprint, GraduationCap, Menu, Monitor, QrCode, ShieldCheck, X } from "lucide-react";
import { chapterAt, chapters } from "./story-model";
import { PublicLinks } from "./PublicPage";
import { PricingSection } from "./PricingSection";
import { ImageStory } from "./ImageStory";
import { ClassroomScene } from "./ClassroomScene";
import styles from "./story.module.css";

const products = [
  { icon: GraduationCap, title: "Student app", detail: "iOS and Android", text: "Check the timetable, scan from a registered phone, and see when attendance is saved or verified." },
  { icon: Monitor, title: "Faculty workspace", detail: "Web portal", text: "Start attendance from an assigned class, project the rotating QR, and review the roster and course register." },
  { icon: ShieldCheck, title: "IT administration", detail: "Web portal", text: "Manage registered devices, approve replacements, and review the history of changes." },
];

const assurance = [
  { icon: QrCode, title: "A QR that refreshes every five seconds", text: "Each signed code belongs to one attendance session and is valid within a short scan window." },
  { icon: Fingerprint, title: "A registered phone for each student", text: "The phone signs the attendance proof with its registered key. The institution controls device replacements." },
  { icon: ShieldCheck, title: "One verified record per session", text: "The backend checks enrollment, signatures, timing and duplicates. Faculty can review exceptions in the attendance workflow." },
];

export function ScrollEditorial({ publicOnly = false }: { publicOnly?: boolean }) {
  const story = useRef<HTMLElement>(null);
  const stage = useRef<HTMLDivElement>(null);
  const menuButton = useRef<HTMLButtonElement>(null);
  const [chapter, setChapter] = useState(0);
  const [manual, setManual] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);

  function geometry() {
    const section = story.current;
    const panel = stage.current;
    if (!section || !panel) return null;
    const stickyTop = Number.parseFloat(getComputedStyle(panel).top) || 0;
    return {
      start: section.getBoundingClientRect().top + scrollY - stickyTop,
      distance: Math.max(1, section.offsetHeight - panel.offsetHeight),
    };
  }

  useEffect(() => {
    const preference = matchMedia("(prefers-reduced-motion: reduce), (max-height: 540px)");
    let frame = 0;
    const update = () => {
      frame = 0;
      if (preference.matches) return;
      const range = geometry();
      if (range) setChapter(chapterAt((scrollY - range.start) / range.distance));
    };
    const schedule = () => { if (!frame) frame = requestAnimationFrame(update); };
    const mode = () => { setManual(preference.matches); schedule(); };
    mode();
    preference.addEventListener("change", mode);
    window.addEventListener("scroll", schedule, { passive: true });
    window.addEventListener("resize", schedule);
    return () => {
      cancelAnimationFrame(frame);
      preference.removeEventListener("change", mode);
      window.removeEventListener("scroll", schedule);
      window.removeEventListener("resize", schedule);
    };
  }, []);

  function jump(index: number) {
    if (manual) {
      setChapter(index);
      return;
    }
    const range = geometry();
    if (range) window.scrollTo({ top: range.start + range.distance * ((index + .5) / chapters.length), behavior: "smooth" });
  }

  return (
    <div className={styles.site}>
      <a className={styles.skip} href="#overview">Skip the animated story</a>
      <header className={styles.navbar} onKeyDown={(event) => {
        if (event.key === "Escape" && menuOpen) {
          setMenuOpen(false);
          menuButton.current?.focus();
        }
      }}>
        <Link href="/" className={styles.brand}><QrCode size={22} aria-hidden="true" />OfflineQR</Link>
        <nav id="editorial-navigation" aria-label="Main navigation" className={menuOpen ? styles.mobileOpen : undefined}>
          <a href="#story" onClick={() => setMenuOpen(false)}>How it works</a>
          <a href="#overview" onClick={() => setMenuOpen(false)}>Platform</a>
          <a href="#pricing" onClick={() => setMenuOpen(false)}>Pricing</a>
        </nav>
        <Link href={publicOnly ? "#pricing" : "/login"} className={styles.signIn}>{publicOnly ? "Plan a deployment" : "Sign in"} <ArrowRight size={15} aria-hidden="true" /></Link>
        <button ref={menuButton} type="button" className={styles.menuToggle} aria-label={menuOpen ? "Close navigation" : "Open navigation"} aria-controls="editorial-navigation" aria-expanded={menuOpen} onClick={() => setMenuOpen(!menuOpen)}>
          {menuOpen ? <X aria-hidden="true" /> : <Menu aria-hidden="true" />}
        </button>
      </header>

      <main>
        <section className={styles.editorialHero}>
          <ClassroomScene />
          <div className={styles.editorialHeadline}>
            <p className={styles.eyebrow}>Attendance for institutions</p>
            <h1>Attendance that <em>works offline.</em></h1>
            <p>Students scan a classroom QR. OfflineQR saves the scan on their phone and verifies it when the connection returns.</p>
            <div className={styles.heroActions}>
              <a className={styles.button} href="#story">See how it works <ArrowDown size={17} aria-hidden="true" /></a>
              <a className={styles.textLink} href="#pricing">View plans <ArrowRight size={16} aria-hidden="true" /></a>
            </div>
          </div>
        </section>

        <section ref={story} id="story" className={styles.story} aria-label="From classroom scan to faculty register">
          <div ref={stage} className={styles.stage}>
            <div className={styles.productFrame}><ImageStory chapter={chapter} /></div>
            <div className={styles.chapterCopy}>
              <div>
                <p className={styles.eyebrow}>How it works</p>
                <h2>{chapters[chapter].title}</h2>
              </div>
              <p>{chapters[chapter].text}</p>
            </div>
            <nav className={styles.chapterNav} aria-label="Story chapters">
              {chapters.map((item, index) => (
                <button key={item.label} type="button" onClick={() => jump(index)} aria-current={chapter === index ? "step" : undefined}>{item.label}</button>
              ))}
            </nav>
          </div>
        </section>

        <section id="overview" className={styles.overview}>
          <div className={styles.sectionHeading}>
            <p className={styles.eyebrow}>The platform</p>
            <h2>One attendance record, <em>three workspaces.</em></h2>
          </div>
          <div className={styles.capabilities}>{products.map(({ icon: Icon, title, detail, text }) => (
            <article key={title}>
              <Icon size={25} strokeWidth={1.5} aria-hidden="true" />
              <div><h3>{title}</h3><p>{text}</p></div>
              <span>{detail}</span>
            </article>
          ))}</div>
        </section>

        <section className={styles.protocol}>
          <div className={styles.sectionHeading}><p className={styles.eyebrow}>Attendance verification</p><h2>What makes a scan <em>count?</em></h2></div>
          <div className={styles.protocolDetails}>{assurance.map(({ icon: Icon, title, text }) => (
            <article key={title}><Icon size={21} aria-hidden="true" /><div><h3>{title}</h3><p>{text}</p></div></article>
          ))}</div>
        </section>

        <PricingSection />
        <section className={styles.faq} aria-labelledby="faq-title">
          <h2 id="faq-title">Common questions</h2>
          <div>
            <details><summary>What happens when there is no internet in class?</summary><p>The student app queues eligible scans on the phone. Faculty can continue hosting an offline session when its signed session package was prepared in advance. The server verifies queued proofs after reconnecting.</p></details>
            <details><summary>Can a scan sync after the faculty ends attendance?</summary><p>Eligible scans captured inside the valid QR window can be submitted after the session closes, within the allowed reconciliation deadline.</p></details>
            <details><summary>How does OfflineQR handle proxy attendance?</summary><p>Short-lived QR codes, registered device keys and duplicate checks limit misuse. The QR alone cannot establish physical proximity.</p></details>
          </div>
        </section>
        <section className={styles.closing}>
          <h2>Plan your institution’s rollout.</h2>
          <p>Estimate annual licensing and download a proposal for your team.</p>
          <a href="#pricing" className={styles.button}>Compare plans <ArrowRight size={17} aria-hidden="true" /></a>
        </section>
      </main>
      <footer className={styles.footer}>
        <Link href="/" className={styles.brand}><QrCode size={22} aria-hidden="true" />OfflineQR</Link>
        <PublicLinks />
        {publicOnly ? null : <Link className={styles.textLink} href="/login">Institutional sign in <ArrowRight size={15} aria-hidden="true" /></Link>}
      </footer>
    </div>
  );
}
