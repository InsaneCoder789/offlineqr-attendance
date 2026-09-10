import Link from "next/link";
import { FileQuestion } from "lucide-react";

export default function NotFound() {
  return (
    <section className="flex min-h-[32rem] flex-col items-center justify-center rounded-lg border bg-card p-8 text-center">
      <span className="flex size-12 items-center justify-center rounded-lg bg-muted text-primary"><FileQuestion className="size-5" /></span>
      <p className="mt-5 text-xs font-semibold uppercase tracking-[0.14em] text-primary">KIIT Attendance</p>
      <h2 className="mt-2 text-3xl font-semibold tracking-tight">Page not found</h2>
      <p className="mt-2 max-w-md text-sm leading-6 text-muted-foreground">The requested workspace page does not exist or is no longer available.</p>
      <Link className="mt-6 inline-flex h-10 items-center justify-center rounded-lg bg-primary px-4 text-sm font-medium text-primary-foreground transition-colors hover:bg-primary/80" href="/dashboard">Return to dashboard</Link>
    </section>
  );
}
