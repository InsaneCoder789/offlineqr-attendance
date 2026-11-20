import { randomUUID } from "node:crypto";
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("./proposal-pdf", () => ({ createProposalPdf: vi.fn(), UnsupportedProposalText: class extends Error {} }));
import { createProposalPdf } from "./proposal-pdf";
import { handleProposal } from "./proposal-http";

const data = { institution: "Example Institute", contact: "billing@example.edu", plan: "core", students: 1000 };
const result = { bytes: new TextEncoder().encode("%PDF-1.7"), reference: "OQR-TEST" };
const generator = vi.mocked(createProposalPdf);
function request(body = JSON.stringify(data), headers: Record<string, string> = {}) {
  return new Request("https://example.test/api/proposals", { method: "POST", body,
    headers: { "Content-Type": "application/json", Origin: "https://example.test", "x-vercel-forwarded-for": randomUUID(), ...headers } });
}
beforeEach(() => { generator.mockReset(); generator.mockResolvedValue(result); });

describe("proposal document endpoint", () => {
  it("returns a private PDF attachment", async () => {
    const response = await handleProposal(request());
    expect(response.status).toBe(200);
    expect(response.headers.get("Content-Type")).toBe("application/pdf");
    expect(response.headers.get("Cache-Control")).toContain("no-store");
    expect(response.headers.get("Content-Disposition")).toContain("OfflineQR-OQR-TEST.pdf");
  });
  it("rejects cross-origin requests before generating documents", async () => {
    expect((await handleProposal(request(undefined, { Origin: "https://untrusted.test" }))).status).toBe(403);
    expect(generator).not.toHaveBeenCalled();
  });
  it("accepts the public Host when Next uses an internal request URL", async () => {
    expect((await handleProposal(request(undefined, { Host: "public.example", Origin: "https://public.example" }))).status).toBe(200);
    expect((await handleProposal(request(undefined, { Origin: "invalid URL" }))).status).toBe(403);
  });
  it("rejects incorrect content types and malformed JSON", async () => {
    expect((await handleProposal(request(undefined, { "Content-Type": "text/plain" }))).status).toBe(415);
    expect((await handleProposal(request("{"))).status).toBe(400);
  });
  it("bounds body size without relying on Content-Length", async () => {
    expect((await handleProposal(request(" ".repeat(8193)))).status).toBe(413);
    expect(generator).not.toHaveBeenCalled();
  });
  it("refuses forged payment and pricing fields", async () => {
    expect((await handleProposal(request(JSON.stringify({ ...data, paymentId: "paid", rate: 1 })))).status).toBe(400);
  });
  it("throttles repeated requests on the same instance", async () => {
    const ip = randomUUID();
    for (let n = 0; n < 6; n++) expect((await handleProposal(request(undefined, { "x-vercel-forwarded-for": ip }))).status).toBe(200);
    const response = await handleProposal(request(undefined, { "x-vercel-forwarded-for": ip }));
    expect(response.status).toBe(429); expect(response.headers.get("Retry-After")).toBe("60");
  });
  it("does not expose internal errors or customer details", async () => {
    generator.mockRejectedValueOnce(new Error("private infrastructure details"));
    const logging = vi.spyOn(console, "error").mockImplementation(() => {});
    try {
      const response = await handleProposal(request());
      expect(response.status).toBe(500);
      expect(await response.text()).not.toContain("private infrastructure details");
      expect(logging).toHaveBeenCalledWith("Proposal PDF generation failed");
    } finally { logging.mockRestore(); }
  });
});
