import styles from "./dark-command.module.css";
import { cn } from "@/lib/utils";

const SIZE = 11;
// Deterministic pseudo-random data modules so SSR and client markup agree.
const cells = Array.from({ length: SIZE * SIZE }, (_, index) => {
  const x = index % SIZE;
  const y = Math.floor(index / SIZE);
  const inFinder = (x < 4 && y < 4) || (x > SIZE - 5 && y < 4) || (x < 4 && y > SIZE - 5);
  const on = ((x * 7 + y * 13 + x * y * 3) % 5) < 2;
  return { x, y, on: on && !inFinder, delay: ((x * 3 + y * 5) % 10) * 0.45 };
}).filter((cell) => cell.on);

/** Decorative rotating-QR motif. Pure SVG + CSS; static under reduced motion. */
export function BrandQrMotif({ glitch = false, className }: { glitch?: boolean; className?: string }) {
  const u = 10;
  const finders = [[0, 0], [SIZE - 3, 0], [0, SIZE - 3]];
  return (
    <svg viewBox={`-6 -6 ${SIZE * u + 12} ${SIZE * u + 12}`} className={cn("h-auto w-full", className)} role="img" aria-label="Decorative rotating QR code" focusable="false">
      <defs><clipPath id={glitch ? "qr-clip-g" : "qr-clip"}><rect x="-4" y="-4" width={SIZE * u + 8} height={SIZE * u + 8} rx="14" /></clipPath></defs>
      <rect className={styles.qrHalo} x="-4" y="-4" width={SIZE * u + 8} height={SIZE * u + 8} rx="14" fill="color-mix(in oklab, var(--primary) 6%, transparent)" stroke="color-mix(in oklab, var(--primary) 35%, transparent)" />
      {cells.map((cell) => (
        <rect key={`${cell.x}-${cell.y}`} className={cn(styles.qrCell, glitch && styles.qrCellGlitch)} x={cell.x * u + 1} y={cell.y * u + 1} width={u - 2} height={u - 2} rx="2.5" style={{ animationDelay: `${cell.delay}s` }} />
      ))}
      {finders.map(([fx, fy]) => (
        <g key={`${fx}-${fy}`}>
          <rect className={styles.qrFinder} x={fx * u + 1} y={fy * u + 1} width={u * 3 - 2} height={u * 3 - 2} rx="6" />
          <rect className={styles.qrFinderDot} x={fx * u + u + 1} y={fy * u + u + 1} width={u - 2} height={u - 2} rx="2.5" />
        </g>
      ))}
      <g clipPath={`url(#${glitch ? "qr-clip-g" : "qr-clip"})`}><rect className={styles.qrSweep} x="-4" y="0" width={SIZE * u + 8} height="3" rx="1.5" /></g>
    </svg>
  );
}
