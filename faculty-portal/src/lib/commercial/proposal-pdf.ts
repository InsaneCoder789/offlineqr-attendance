import { readFile } from "node:fs/promises";
import path from "node:path";
import { randomBytes } from "node:crypto";
import { PDFDocument, rgb, type PDFFont, type PDFPage } from "pdf-lib";
import fontkit from "@pdf-lib/fontkit";
import { proposalPrice, type ProposalInput } from "./proposal-model";

const W = 595.28, H = 841.89, M = 48, CW = W - 2 * M;
const ink = rgb(.12, .19, .16), green = rgb(.14, .48, .32);
const muted = rgb(.39, .45, .42), ruleColor = rgb(.86, .89, .87);
let assets: Promise<Buffer[]> | undefined;

function loadAssets() {
  // Only immutable public branding is cached. Customer data and PDFs are never cached.
  return assets ??= Promise.all(["Manrope-Regular.ttf", "Manrope-SemiBold.ttf", "Manrope-Bold.ttf", "logo.png"]
    .map(name => readFile(path.join(process.cwd(), "server-assets/commercial", name))));
}

export class UnsupportedProposalText extends Error {}

export async function createProposalPdf(input: ProposalInput, now = new Date()) {
  const [regularBytes, semiBytes, boldBytes, logoBytes] = await loadAssets();
  const document = await PDFDocument.create();
  document.registerFontkit(fontkit);
  const [regular, semi, bold, logo] = await Promise.all([
    document.embedFont(regularBytes, { subset: true }), document.embedFont(semiBytes, { subset: true }),
    document.embedFont(boldBytes, { subset: true }), document.embedPng(logoBytes),
  ]);
  const supported = new Set(regular.getCharacterSet());
  for (const value of [input.institution, input.contact, input.contactName, input.address, input.requirements]) {
    if ([...value].some(char => !supported.has(char.codePointAt(0)!))) {
      throw new UnsupportedProposalText("Please use Latin characters for this document's billing details.");
    }
  }
  const reference = `OQR-${randomBytes(12).toString("hex").toUpperCase()}`;
  const draftOrderReference = `DRAFT-${randomBytes(12).toString("hex").toUpperCase()}`;
  const date = new Intl.DateTimeFormat("en-GB", { timeZone: "Asia/Kolkata", day: "2-digit", month: "short", year: "numeric" }).format(now);
  const price = proposalPrice(input);
  const money = (value: number | null) => value === null ? "To be quoted" : `INR ${value.toLocaleString("en-IN")}`;
  document.setTitle("OfflineQR - Deployment Proposal and Pro Forma Invoice");
  document.setAuthor("OfflineQR");
  document.setSubject("Indicative proposal only; not an order confirmation, tax invoice or receipt");
  document.setCreationDate(now);

  function text(page: PDFPage, value: string, x: number, top: number, size = 10, font: PDFFont = regular, color = ink, right = false) {
    page.drawText(value, { x: right ? x - font.widthOfTextAtSize(value, size) : x, y: H - top - size, size, font, color });
  }
  function line(page: PDFPage, top: number, x = M, width = CW, color = ruleColor) {
    page.drawLine({ start: { x, y: H - top }, end: { x: x + width, y: H - top }, color, thickness: .6 });
  }
  function rowsFor(value: string, width: number, size: number) {
    const rows: string[] = [];
    let row = "";
    for (const word of value.split(/\s+/)) {
      const candidate = row ? `${row} ${word}` : word;
      if (regular.widthOfTextAtSize(candidate, size) <= width) { row = candidate; continue; }
      if (row) { rows.push(row); row = ""; }
      if (regular.widthOfTextAtSize(word, size) <= width) { row = word; continue; }
      for (const char of word) {
        if (regular.widthOfTextAtSize(row + char, size) > width) { rows.push(row); row = ""; }
        row += char;
      }
    }
    if (row.trim()) rows.push(row.trim());
    return rows;
  }
  function paragraph(page: PDFPage, value: string, top: number, x = M, width = CW, size = 10, leading = 17, color = ink) {
    const rows = rowsFor(value, width, size);
    rows.forEach((value, index) => text(page, value, x, top + index * leading, size, regular, color));
    return top + rows.length * leading;
  }
  function fitParagraph(page: PDFPage, value: string, top: number, x: number, width: number, height: number, size: number, color = ink) {
    while (size >= 7) {
      const leading = size * 1.4;
      if (rowsFor(value, width, size).length * leading <= height) return paragraph(page, value, top, x, width, size, leading, color);
      size -= .5;
    }
    throw new UnsupportedProposalText("Please shorten your institution name or billing details so they fit the document.");
  }
  function header(page: PDFPage, number: number) {
    page.drawImage(logo, { x: M, y: H - 85, width: 42, height: 42 });
    text(page, "OfflineQR", M + 55, 42, 27, bold);
    text(page, "Presence, without interruption.", M + 55, 77, 9, regular, muted);
    text(page, "offlineqr-editorial.vercel.app", W - M, 51, 8, regular, muted, true);
    text(page, "Institutional attendance solutions", W - M, 68, 8, regular, muted, true);
    line(page, 108);
    [[M, "Dynamic QR", "Five-second rotation"], [M + 174, "Offline continuity", "Capture now. Verify on sync."],
      [M + 348, "Device-bound identity", "Controlled device replacement"]].forEach(([x, title, detail]) => {
      text(page, String(title), Number(x), 124, 9, semi, green);
      text(page, String(detail), Number(x), 143, 7.8, regular, muted);
    });
    line(page, 171, M, CW, green);
    line(page, 777);
    text(page, "OfflineQR | Commercial proposal", M, 793, 7.5, semi, muted);
    text(page, `0${number} / 02`, W - M, 793, 7.5, regular, muted, true);
    text(page, "Indicative proposal. No order, payment or access has been confirmed.", M, 808, 7, regular, muted);
  }

  const letter = document.addPage([W, H]); header(letter, 1);
  text(letter, "Deployment proposal", M, 195, 22, bold);
  text(letter, reference, W - M, 201, 7, regular, muted, true);
  text(letter, date, W - M, 219, 8, regular, muted, true);
  text(letter, "Prepared for", M, 247, 8, semi, muted);
  fitParagraph(letter, input.institution, 266, M, CW, 32, 13);
  if (input.contactName) fitParagraph(letter, input.contactName, 304, M, CW, 16, 9, muted);
  fitParagraph(letter, input.contact, 325, M, CW, 24, 8, muted);
  line(letter, 360);
  text(letter, "Dear Authorized Representative,", M, 378, 10, semi);
  let y = paragraph(letter, "We propose OfflineQR for your institution: one attendance workflow connecting students, faculty and administrators, with continuity when classroom connectivity is unreliable.", 406);
  y = paragraph(letter, "Faculty display a signed classroom QR that rotates every five seconds. Students scan using their registered app. Offline proofs stay on the phone and undergo server verification when the service becomes reachable.", y + 14);
  y = paragraph(letter, "Faculty can review attendance registers and synchronization outcomes. Administrative controls govern device replacement and retain a reviewable history of decisions.", y + 14);
  line(letter, y + 22); y += 42;
  for (const [label, value] of [["Proposed package", price.name], ["Licence scope", `${input.students.toLocaleString("en-IN")} students / annual licence`], ["Indicative licence", money(price.subtotal)]]) {
    text(letter, label, M, y, 9, semi); text(letter, value, M + 142, y, 9, regular, muted); y += 22;
  }
  paragraph(letter, "Final scope, taxes, hosting and implementation terms require agreement. Once an order is approved and payment verified, billing documents and a separate secure access invitation can be issued to your designated contact.", y + 11, M, CW, 9.5, 16);
  text(letter, "Yours sincerely,", M, 722, 9.5);
  text(letter, "OfflineQR", M, 742, 11, bold);
  text(letter, "Institutional attendance solutions", M, 760, 8, regular, muted);

  const invoice = document.addPage([W, H]); header(invoice, 2);
  text(invoice, "Pro forma invoice", M, 195, 22, bold);
  text(invoice, "Indicative quotation only. Not a tax invoice.", M, 227, 8.5, regular, muted);
  text(invoice, reference, W - M, 201, 7, regular, muted, true);
  text(invoice, `Draft order: ${draftOrderReference}`, W - M, 220, 6.8, regular, muted, true);
  text(invoice, date, W - M, 238, 8, regular, muted, true);
  text(invoice, "From", M, 270, 8, semi, muted);
  text(invoice, "OfflineQR", M, 287, 10, semi);
  paragraph(invoice, "Supplier legal and tax particulars will be confirmed in the final quotation.", 307, M, 231, 9, 14, muted);
  text(invoice, "Bill to", M + 266, 270, 8, semi, muted);
  fitParagraph(invoice, input.institution, 287, M + 266, CW - 266, 31, 9);
  fitParagraph(invoice, input.address || "Billing address to be confirmed", 322, M + 266, CW - 266, 60, 8, muted);
  line(invoice, 385);
  invoice.drawRectangle({ x: M, y: H - 431, width: CW, height: 30, color: rgb(.94, .965, .95) });
  text(invoice, "Description", M + 10, 410, 8, semi, green);
  text(invoice, "Qty", M + 270, 410, 8, semi, green);
  text(invoice, "Rate / INR", M + 347, 410, 8, semi, green);
  text(invoice, "Amount / INR", W - M - 10, 410, 8, semi, green, true);
  text(invoice, `OfflineQR ${price.name} licence`, M + 10, 448, 9.5, semi);
  text(invoice, "Annual licence / indicative pricing", M + 10, 468, 8, regular, muted);
  text(invoice, input.students.toLocaleString("en-IN"), M + 270, 450, 9, regular, muted);
  text(invoice, price.rate === null ? "Custom" : String(price.rate), M + 347, 450, 9, regular, muted);
  text(invoice, price.subtotal === null ? "To be quoted" : price.subtotal.toLocaleString("en-IN"), W - M - 10, 450, 9, regular, muted, true);
  line(invoice, 499);
  text(invoice, "Commercial terms", M, 524, 8, semi, muted);
  paragraph(invoice, "Annual licensing. Customization, implementation and support are scoped separately. No payment is collected by this document.", 546, M, 233, 9, 15, muted);
  for (const [top, label, value] of [[523, "Subtotal", money(price.subtotal)], [553, "Tax", "To be confirmed"],
    [595, "Total", price.subtotal === null ? "To be quoted" : `${money(price.subtotal)} + tax`]] as const) {
    text(invoice, label, M + 290, top, 9, semi);
    text(invoice, value, W - M, top, 8.5, top === 595 ? bold : regular, top === 595 ? green : muted, true);
  }
  line(invoice, 584, M + 290, CW - 290);
  line(invoice, 636);
  text(invoice, "Requested customization", M, 657, 9, semi, green);
  fitParagraph(invoice, input.requirements || "No additional requirements supplied.", 679, M, CW, 48, 9, muted);
  text(invoice, "Payment ID: not assigned", M, 737, 8, regular, muted);
  text(invoice, "Payment status: not collected", M + 266, 737, 8, regular, muted);
  text(invoice, "Secure access is issued separately only after order approval and verified payment.", M, 757, 7.2, regular, muted);
  return { bytes: await document.save(), reference };
}
