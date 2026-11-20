"use client";

import { useEffect, useRef, useState } from "react";
import { ArrowRight, Check, Download, LoaderCircle, X } from "lucide-react";
import { annualEstimate, plans } from "./story-model";
import styles from "./story.module.css";

const money = (value: number) => new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", maximumFractionDigits: 0 }).format(value);

export function PricingSection() {
  const [students, setStudents] = useState(1000);
  const [selected, setSelected] = useState("institution");
  const [downloaded, setDownloaded] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const pending = useRef<AbortController | null>(null);
  const dialog = useRef<HTMLDialogElement>(null);
  const plan = plans.find(item => item.id === selected);
  useEffect(() => () => { pending.current?.abort(); pending.current = null; }, []);
  function cancel() { pending.current?.abort(); pending.current = null; setBusy(false); }
  function open(id: string) { cancel(); setSelected(id); setDownloaded(false); setError(""); dialog.current?.showModal(); }
  async function download(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (pending.current) return;
    const form = new FormData(event.currentTarget);
    const value = (name: string) => String(form.get(name) ?? "").replace(/\s+/g, " ").trim();
    const controller = new AbortController(); pending.current = controller;
    setBusy(true); setDownloaded(false); setError("");
    try {
      const response = await fetch("/api/proposals", { method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ institution: value("institution"), contact: value("contact"), contactName: value("contactName"),
          address: value("address"), requirements: value("requirements"), plan: selected, students }), signal: controller.signal });
      if (!response.ok) {
        const detail = await response.json().catch(() => null);
        throw new Error(detail?.error || "Your PDF could not be generated. Please try again.");
      }
      if (!response.headers.get("Content-Type")?.includes("application/pdf")) throw new Error("The document service returned an unexpected response.");
      const blob = await response.blob();
      if (pending.current !== controller) return;
      const href = URL.createObjectURL(blob);
      const anchor = document.createElement("a"); anchor.href = href;
      anchor.download = response.headers.get("Content-Disposition")?.match(/filename="([A-Za-z0-9.-]+)"/)?.[1] ?? "OfflineQR-Proposal.pdf";
      document.body.append(anchor); anchor.click(); anchor.remove();
      setTimeout(() => URL.revokeObjectURL(href), 10000); setDownloaded(true);
    } catch (cause) {
      if (pending.current === controller && !controller.signal.aborted) setError(cause instanceof Error ? cause.message : "Check your connection and try again.");
    } finally { if (pending.current === controller) { pending.current = null; setBusy(false); } }
  }
  return <section id="pricing" className={styles.pricing}>
    <div className={styles.sectionHeading}><p>03 / A model that fits your institution</p><h2>Start with the classroom.<br /><span>Scale with your campus.</span></h2><p>Annual licensing per enrolled student. Choose your scope, then shape the deployment around your institution.</p></div>
    <div className={styles.priceControls}><label htmlFor="enrollment">Enrolled students <input id="enrollment" type="number" min={100} max={100000} step={100} value={students} onChange={e => setStudents(Math.max(100, Math.min(100000, Number(e.target.value) || 100)))} /></label><span>Launch pricing proposal · INR · annual billing</span></div>
    <div className={styles.planGrid}>{plans.map(item => <article key={item.id} className={item.id === "institution" ? styles.featuredPlan : undefined}>
      <h3>{item.name}</h3><p>{item.description}</p><div className={styles.rate}>{money(item.rate)}<span>/ student / year</span></div><p className={styles.estimate}>{money(annualEstimate(item.rate, students))} / year for {students.toLocaleString("en-IN")} students</p><ul>{item.features.map(feature => <li key={feature}><Check size={15} />{feature}</li>)}</ul><button onClick={() => open(item.id)} className={styles.button}>Plan this deployment <ArrowRight size={16} /></button>
    </article>)}<article><h3>Enterprise</h3><p>For institution groups and specialized operational requirements.</p><div className={styles.rate}>Let&apos;s scope it.</div><p className={styles.estimate}>A tailored commercial proposal</p><ul>{["Multi-campus deployment scoping", "Identity and academic integration planning", "Hosting, support and security requirements", "Customized rollout and governance"].map(feature => <li key={feature}><Check size={15} />{feature}</li>)}</ul><button onClick={() => open("enterprise")} className={styles.button}>Build a brief <ArrowRight size={16} /></button></article></div>
    <p className={styles.priceNote}>Indicative pricing, not an offer or an active subscription. Taxes, onboarding, integrations and support terms are scoped separately. Tenant isolation and billing must be completed before a shared SaaS launch.</p>
    <dialog ref={dialog} className={styles.drawer} aria-labelledby="proposal-title" onClose={cancel}><div className={styles.drawerHeader}><span>YOUR DEPLOYMENT</span><button aria-label="Close deployment planner" title="Close deployment planner" onClick={() => dialog.current?.close()}><X /></button></div><h2 id="proposal-title">Make OfflineQR<br />your own.</h2><p>{plan?.name ?? "Enterprise"} · {students.toLocaleString("en-IN")} students{plan ? ` · ${money(annualEstimate(plan.rate, students))} indicative annual license` : ""}</p>
      <form onSubmit={download} aria-busy={busy}><label>Institution name<input name="institution" required minLength={2} maxLength={100} autoComplete="organization" disabled={busy} /></label><label>Contact name<input name="contactName" maxLength={60} autoComplete="name" disabled={busy} /></label><label>Contact email<input name="contact" type="email" required maxLength={120} autoComplete="email" disabled={busy} /></label><label>Billing address<input name="address" maxLength={180} autoComplete="street-address" disabled={busy} /></label><label>Your requirements<textarea name="requirements" rows={3} maxLength={240} placeholder="Branding, academic systems, hosting and rollout" disabled={busy} /></label><button className={styles.button} type="submit" disabled={busy}>{busy ? <LoaderCircle size={16} className={styles.proposalSpinner} /> : <Download size={16} />}{busy ? "Preparing your PDF" : "Download proposal PDF"}</button>{error && <p className={styles.proposalError} role="alert">{error}</p>}<p role="status">{downloaded ? "Proposal PDF downloaded. No order or payment has been confirmed." : "Your details are sent to generate the PDF. They are not stored or emailed. No payment is collected."}</p></form>
    </dialog>
  </section>;
}
