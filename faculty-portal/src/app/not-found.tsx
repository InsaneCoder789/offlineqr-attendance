import Link from "next/link";
import { FileQuestion } from "lucide-react";

export default function NotFound() {
  return (
    <main className="flex min-h-dvh flex-col items-center justify-center bg-background px-4 py-10 text-center">
      <span className="flex size-14 items-center justify-center rounded-2xl bg-primary/10 text-primary"><FileQuestion className="size-6" aria-hidden="true" /></span>
      <p className="mt-5 text-xs font-semibold uppercase tracking-[0.14em] text-primary">OfflineQR</p>
      <h1 className="mt-2 text-fluid-2xl font-semibold tracking-tight">Page not found</h1>
      <p className="mt-2 max-w-md text-pretty text-sm leading-6 text-muted-foreground">The requested page does not exist or is no longer available.</p>
      <Link className="mt-6 inline-flex min-h-11 items-center justify-center rounded-lg bg-primary px-5 text-sm font-medium text-primary-foreground transition-colors hover:bg-primary/85 focus-visible:ring-3 focus-visible:ring-ring/50" href="/">Return to OfflineQR</Link>
    </main>
  );
}
