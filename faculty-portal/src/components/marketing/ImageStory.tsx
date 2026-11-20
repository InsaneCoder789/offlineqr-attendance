"use client";

import Image from "next/image";
import styles from "./image-story.module.css";

const frames = ["classroom", "scan", "offline", "reconcile"];
const descriptions = [
  "Student timetable beside a faculty laptop with a live attendance QR",
  "Student phone captures the classroom QR and signs a scan",
  "Phone stores attendance offline while awaiting synchronization",
  "Phone shows server-accepted attendance and the faculty roster updates",
];

export function ImageStory({ chapter }: { chapter: number }) {
  const selected = Math.max(0, Math.min(3, chapter));
  return <div className={styles.scene} data-story-frame={frames[selected]}>
    <div className={styles.plate} role="img" aria-label={descriptions[selected]}>
      <Image src="/branding/story-locked-v2/classroom.png" alt="" fill priority sizes="(max-width: 700px) 114vw, (max-width: 1440px) 90vw, 1440px" />
      {frames.slice(1).map((name, index) => <div key={name} className={`${styles.screenLayer} ${selected === index + 1 ? styles.active : ""}`} aria-hidden="true">
        <div className={styles.phoneWindow}><Image src={`/branding/story-locked-v2/${name}.png`} alt="" fill loading="eager" sizes="(max-width: 700px) 114vw, (max-width: 1440px) 90vw, 1440px" /></div>
        {name === "reconcile" ? <div className={styles.laptopWindow}><Image src={`/branding/story-locked-v2/${name}.png`} alt="" fill loading="eager" sizes="(max-width: 700px) 114vw, (max-width: 1440px) 90vw, 1440px" /></div> : null}
      </div>)}
    </div>
  </div>;
}
