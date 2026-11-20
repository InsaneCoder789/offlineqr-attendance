import { createProposalPdf, UnsupportedProposalText } from "./proposal-pdf";
import { proposalSchema } from "./proposal-model";

const MAX_BODY_BYTES = 8192;
const noStore = { "Cache-Control": "private, no-store", "X-Content-Type-Options": "nosniff" };
const error = (message: string, status: number) => Response.json({ error: message }, { status, headers: noStore });
const buckets = new Map<string, { count: number; until: number }>();
let active = 0;

function allowed(request: Request) {
  // Best-effort instance limits; production edge/Redis limits are required for distributed abuse protection.
  const now = Date.now();
  for (const [key, bucket] of buckets) if (bucket.until <= now) buckets.delete(key);
  const key = request.headers.get("x-vercel-forwarded-for") ?? request.headers.get("x-forwarded-for") ?? "local";
  let bucket = buckets.get(key);
  if (!bucket) {
    if (buckets.size >= 1000) return false;
    bucket = { count: 0, until: now + 60000 }; buckets.set(key, bucket);
  }
  return ++bucket.count <= 6;
}

async function readBoundedBody(request: Request) {
  if (!request.body) return "";
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = []; let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > MAX_BODY_BYTES) { await reader.cancel(); return null; }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return new TextDecoder().decode(bytes);
}

export async function handleProposal(request: Request) {
  const origin = request.headers.get("origin");
  const url = new URL(request.url);
  let sameOrigin = true;
  if (origin) {
    try { const source = new URL(origin); sameOrigin = source.host === (request.headers.get("host") ?? url.host) && source.protocol === url.protocol; }
    catch { sameOrigin = false; }
  }
  if (!sameOrigin || request.headers.get("sec-fetch-site") === "cross-site") {
    return error("Please generate the proposal from the OfflineQR website.", 403);
  }
  if (request.headers.get("content-type")?.split(";")[0].trim() !== "application/json") {
    return error("Send proposal details as JSON.", 415);
  }
  if (Number(request.headers.get("content-length")) > MAX_BODY_BYTES) return error("Proposal details are too large.", 413);
  if (!allowed(request)) return Response.json({ error: "Too many proposals. Please try again in a minute." }, { status: 429, headers: { ...noStore, "Retry-After": "60" } });
  if (active >= 3) return error("The document service is busy. Please try again shortly.", 503);
  active++;
  try {
    const body = await readBoundedBody(request);
    if (body === null) return error("Proposal details are too large.", 413);
    let raw: unknown;
    try { raw = JSON.parse(body); } catch { return error("Proposal details could not be read.", 400); }
    const result = proposalSchema.safeParse(raw);
    if (!result.success) return error("Check your institution, contact email, plan, student count and field lengths.", 400);
    const { bytes, reference } = await createProposalPdf(result.data);
    return new Response(new Uint8Array(bytes), { headers: { ...noStore, "Content-Type": "application/pdf",
      "Content-Disposition": `attachment; filename="OfflineQR-${reference}.pdf"` } });
  } catch (cause) {
    if (cause instanceof UnsupportedProposalText) return error(cause.message, 400);
    // Do not log customer payloads or expose library errors to the client.
    console.error("Proposal PDF generation failed");
    return error("We could not generate your PDF. Please try again shortly.", 500);
  } finally { active--; }
}
