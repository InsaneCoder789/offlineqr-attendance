import Link from "next/link";

export default function NotFound() {
  return (
    <main className="login-page">
      <section className="login-card">
        <p className="eyeline">KIIT Faculty Portal</p>
        <h1>Page not found</h1>
        <p>The requested faculty workspace page does not exist.</p>
        <Link className="button-link" href="/dashboard">Return to dashboard</Link>
      </section>
    </main>
  );
}
