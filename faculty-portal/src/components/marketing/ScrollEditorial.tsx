"use client";

import Link from "next/link";
import "@fontsource-variable/manrope";
import "@fontsource-variable/dm-sans";
import { useEffect, useRef, useState } from "react";
import { ArrowDown, ArrowRight, Fingerprint, Menu, QrCode, ShieldCheck, WifiOff, X } from "lucide-react";
import { chapterAt, chapters, mobileChapterText } from "./story-model";
import { PricingSection } from "./PricingSection";
import { ImageStory } from "./ImageStory";
import styles from "./story.module.css";

export function ScrollEditorial({ publicOnly = false }: { publicOnly?: boolean }) {
  const story = useRef<HTMLElement>(null);
  const [chapter, setChapter] = useState(0);
  const [intro, setIntro] = useState(true);
  const [reduced, setReduced] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  useEffect(() => {
    const preference = matchMedia("(prefers-reduced-motion: reduce)");
    const motion = () => setReduced(preference.matches); motion(); preference.addEventListener("change", motion);
    let frame = 0;
    const update = () => { frame = 0; if (!story.current) return; const bounds = story.current.getBoundingClientRect(); const progress = -bounds.top / Math.max(1, bounds.height - innerHeight); setChapter(chapterAt(progress)); setIntro(progress < .1); };
    const scroll = () => { if (!frame) frame = requestAnimationFrame(update); }; scroll();
    window.addEventListener("scroll", scroll, { passive: true }); window.addEventListener("resize", scroll);
    return () => { cancelAnimationFrame(frame); window.removeEventListener("scroll", scroll); window.removeEventListener("resize", scroll); preference.removeEventListener("change", motion); };
  }, []);
  function jump(index: number) { const section = story.current; if (!section) return; const top = section.getBoundingClientRect().top + scrollY; window.scrollTo({ top: top + (section.offsetHeight - innerHeight) * (index / 4 + .13), behavior: reduced ? "instant" : "smooth" }); }
  return <div className={styles.site}>
    <a className={styles.skip} href="#overview">Skip the animated story</a>
    <header className={styles.navbar}><Link href="/" className={styles.brand}><QrCode size={24} />OfflineQR<span /></Link><nav aria-label="Main navigation" className={menuOpen ? styles.mobileOpen : undefined}><a href="#story" onClick={() => setMenuOpen(false)}>The experience</a><a href="#overview" onClick={() => setMenuOpen(false)}>The platform</a><a href="#pricing" onClick={() => setMenuOpen(false)}>Pricing</a></nav><Link href={publicOnly ? "#pricing" : "/login"} className={styles.signIn}>{publicOnly ? "Get started" : "Sign in"} <ArrowRight size={15} /></Link><button className={styles.menuToggle} aria-label={menuOpen ? "Close navigation" : "Open navigation"} aria-expanded={menuOpen} onClick={() => setMenuOpen(!menuOpen)}>{menuOpen ? <X /> : <Menu />}</button></header>
    <main>
      <section ref={story} id="story" className={styles.story} aria-label="From classroom scan to faculty register">
        <div className={styles.stage}>
          <div className={`${styles.heroCopy} ${intro ? styles.visible : ""}`} aria-hidden={!intro}><h1>OfflineQR</h1><p className={styles.heroLine}>Presence, without interruption.</p><p className={styles.heroDescription}>A student app. A faculty workspace. Attendance that stays<br className={styles.desktopBreak} /> with the classroom, even when the connection doesn&apos;t.</p></div>
          <ImageStory chapter={chapter} />
          <div className={`${styles.chapterCopy} ${!intro ? styles.visible : ""}`} aria-hidden={intro}><h2>{chapters[chapter].title}</h2><p className={styles.desktopChapterText}>{chapters[chapter].text}</p><p className={styles.mobileChapterText}>{mobileChapterText[chapter]}</p></div>
          <div className={styles.stageFooter}><button onClick={() => chapter === 3 ? document.getElementById("overview")?.scrollIntoView({ behavior: reduced ? "instant" : "smooth" }) : jump(chapter + (intro ? 0 : 1))} aria-label="Continue the attendance story"><ArrowDown size={20} /></button></div>
          <nav className={styles.chapterNav} aria-label="Story chapters">{chapters.map((item, index) => <button key={item.label} onClick={() => jump(index)} aria-current={chapter === index ? "step" : undefined}>{item.label}</button>)}</nav>
        </div>
      </section>
      <p className={styles.storyCaption}>Illustrative screens. Server verification determines final attendance.</p>
      <section id="overview" className={styles.overview}><div className={styles.sectionHeading}><p>01 / Built around real academic routines</p><h2>Less administration.<br /><span>More room to teach.</span></h2><p>One workflow connects a student&apos;s day, the faculty register and administrative device control. No roll-call spreadsheet handoff. No confusion between a saved scan and a verified record.</p></div><div className={styles.capabilities}>{[{ icon: QrCode, title: "For the student", text: "Timetable, personal attendance, an in-app scanner and institution services. Every captured proof has a visible local and synchronization state.", detail: "iOS + Android" }, { icon: WifiOff, title: "For the faculty", text: "Assigned classes, rotating classroom QR, live roster, projector view and course registers. Offline hosting requires a prepared, signed session package.", detail: "Web workspace" }, { icon: ShieldCheck, title: "For the administrator", text: "One active attendance credential per student. Controlled replacement, revoked credentials and a history of administrative decisions.", detail: "Device governance" }].map(({ icon: Icon, title, text, detail }) => <article key={title}><Icon size={25} strokeWidth={1.5} /><h3>{title}</h3><p>{text}</p><span>{detail}</span></article>)}</div></section>
      <section className={styles.protocol}><div><p>02 / Accountability, not impossible promises</p><h2>A signed trail.<br /><span>Not a blind trust.</span></h2></div><div className={styles.protocolDetails}><article><QrCode size={21} /><div><h3>Rotating, time-bound QR</h3><p>A new QR every five seconds. The current implementation enforces a five-second signed scan window with clock tolerance; the claim-creation allowance is separate.</p></div></article><article><Fingerprint size={21} /><div><h3>Identity bound to a credential</h3><p>Enrollment and registered-key signatures tie a proof to a student. Device metadata is audit evidence, not a guarantee against spoofing.</p></div></article><article><ShieldCheck size={21} /><div><h3>Verification before acceptance</h3><p>The backend checks signatures, session eligibility and duplicates. QR alone cannot prove physical proximity; administrative exceptions remain auditable.</p></div></article></div></section>
      <PricingSection />
      <section className={styles.closing}><p>Bring the record closer to the classroom.</p><h2>Your institution.<br /><span>One connected attendance flow.</span></h2><a href="#pricing" className={styles.button}>Shape your deployment <ArrowRight size={17} /></a></section>
    </main>
    <footer className={styles.footer}><Link href="/" className={styles.brand}><QrCode size={22} />OfflineQR</Link><span>Attendance, beyond the connection.</span><Link href={publicOnly ? "#pricing" : "/login"}>{publicOnly ? "Plan your deployment" : "Institutional sign in"} <ArrowRight size={15} /></Link></footer>
  </div>;
}
