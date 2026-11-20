import type { LucideIcon } from "lucide-react";
import styles from "./ops.module.css";

/** Designed empty / closed / no-session state used across the command-centre views. */
export function StatePanel({ icon: Icon, title, text, action, tone }: { icon: LucideIcon; title: string; text: string; action?: React.ReactNode; tone?: "warn" | "bad" }) {
  const color = tone === "warn" ? "var(--o-warn)" : tone === "bad" ? "var(--o-bad)" : undefined;
  return (
    <div className={`${styles.glass} ${styles.statePanel}`}>
      <span className={styles.stateIcon} style={color ? ({ "--tone": color } as React.CSSProperties) : undefined}><Icon aria-hidden="true" /></span>
      <h3 className={styles.stateTitle}>{title}</h3>
      <p className={styles.stateText}>{text}</p>
      {action}
    </div>
  );
}
