"""Render OfflineQR's branded proposal letter and pro forma invoice."""
from pathlib import Path
from tempfile import TemporaryDirectory
from fontTools.ttLib import TTFont as FontFile
from fontTools.varLib.instancer import instantiateVariableFont
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.platypus import Paragraph
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.graphics import renderPDF
from svglib.svglib import svg2rlg
from pypdf import PdfReader

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "output/pdf/OfflineQR_Proposal_Invoice_Order_Template.pdf"
W, H = A4
M = 48
CW = W - M * 2
INK, GREEN, MUTED, RULE, PALE, PLACEHOLDER = map(HexColor,
    ["#1F3029", "#247A51", "#63726B", "#DBE3DF", "#F0F6F2", "#75857C"])


def generate():
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    c = canvas.Canvas(str(OUTPUT), pagesize=A4)
    c.setTitle("OfflineQR - Commercial Proposal and Pro Forma Invoice")
    c.setAuthor("OfflineQR")
    c.setSubject("Branded commercial template; not an issued invoice or payment receipt")

    def text(value, x, top, size=10, weight="Regular", color=INK, right=False):
        c.setFillColor(color)
        c.setFont(f"Manrope{weight}", size)
        (c.drawRightString if right else c.drawString)(x, H-top-size, value)

    def paragraph(value, top, x=M, width=CW, size=10, color=INK, leading=17):
        style = ParagraphStyle("body", fontName="ManropeRegular", fontSize=size,
                               leading=leading, textColor=color)
        p = Paragraph(value, style)
        _, height = p.wrap(width, H)
        p.drawOn(c, x, H-top-height)
        return top+height

    def rule(top, x=M, width=CW, color=RULE):
        c.setStrokeColor(color)
        c.setLineWidth(.6)
        c.line(x, H-top, x+width, H-top)

    def label_value(label, value, x, top, width=230):
        text(label, x, top, 8, "SemiBold", MUTED)
        paragraph(value, top+17, x, width, 10, PLACEHOLDER, 15)

    def header(page):
        logo = svg2rlg(str(ROOT / "faculty-portal/public/branding/offlineqr-mark.svg"))
        logo.scale(42/logo.width, 42/logo.height)
        renderPDF.draw(logo, c, M, H-85)
        text("OfflineQR", M+55, 42, 27, "Bold")
        text("Presence, without interruption.", M+55, 77, 9, color=MUTED)
        text("offlineqr-editorial.vercel.app", W-M, 51, 8, color=MUTED, right=True)
        text("Institutional attendance solutions", W-M, 68, 8, color=MUTED, right=True)
        rule(108)
        for x, title, detail in [
            (M, "Dynamic QR", "Five-second rotation"),
            (M+174, "Offline continuity", "Capture now. Verify on sync."),
            (M+348, "Device-bound identity", "Controlled device replacement"),
        ]:
            text(title, x, 124, 9, "SemiBold", GREEN)
            text(detail, x, 143, 7.8, color=MUTED)
        rule(171, color=GREEN)
        rule(777)
        text("OfflineQR  |  Commercial proposal", M, 793, 7.5, "SemiBold", MUTED)
        text(f"{page:02d} / 02", W-M, 793, 7.5, color=MUTED, right=True)
        text("Template - complete and authorize before issue.", M, 808, 7, color=MUTED)

    header(1)
    text("Deployment proposal", M, 195, 22, "Bold")
    text("Proposal ID: [Proposal reference]", W-M, 201, 8, color=PLACEHOLDER, right=True)
    text("Date: [Issue date]", W-M, 219, 8, color=PLACEHOLDER, right=True)
    text("Prepared for", M, 247, 8, "SemiBold", MUTED)
    text("[Institution name]", M, 266, 14, "SemiBold", PLACEHOLDER)
    text("[Contact name and designation]", M, 291, 9, color=PLACEHOLDER)
    text("[Institution address]", M, 310, 9, color=PLACEHOLDER)
    rule(340)
    text("Dear [Contact name],", M, 361, 10, "SemiBold")
    y = paragraph("We propose OfflineQR for your institution: one attendance workflow connecting students, faculty and administrators, with continuity when classroom connectivity is unreliable.", 389)
    y = paragraph("Faculty open a class and display a signed QR that rotates every five seconds. Students scan through their registered mobile app. Offline scans are retained on the device and submitted for server verification once the service becomes reachable.", y+14)
    y = paragraph("Your faculty gain a shared attendance register; students can review their records and synchronization status. Administrative controls govern device replacement and preserve a reviewable history of decisions.", y+14)
    rule(y+23)
    top = y+43
    for label, value in [
        ("Proposed package", "[Selected plan and agreed customization]"),
        ("Licence scope", "[Student count] students  /  [Licence term]"),
        ("Delivery", "[Agreed implementation schedule]"),
    ]:
        text(label, M, top, 9, "SemiBold")
        text(value, M+142, top, 9, color=PLACEHOLDER)
        top += 22
    paragraph("Upon acceptance, we will issue the final order and payment instructions. Following payment verification, billing documents and a separate secure access invitation will be sent to your designated contact.", top+11, size=9.5, leading=16)
    text("Yours sincerely,", M, 696, 9.5)
    text("[Authorized signatory]", M, 720, 10, "SemiBold", PLACEHOLDER)
    text("OfflineQR  |  [Legal trading name]", M, 740, 8.5, color=MUTED)
    c.showPage()

    header(2)
    text("Pro forma invoice", M, 195, 22, "Bold")
    text("Quotation only. Not a tax invoice.", M, 227, 8.5, color=MUTED)
    text("Reference: [Invoice reference]", W-M, 200, 8, color=PLACEHOLDER, right=True)
    text("Order ID: [Order reference]", W-M, 218, 8, color=PLACEHOLDER, right=True)
    text("Issued: [Date]  |  Valid until: [Date]", W-M, 236, 8, color=PLACEHOLDER, right=True)
    label_value("From", "[Supplier legal name]<br/>[Registered address]<br/>[Billing email]  /  [Tax ID, if applicable]", M, 270, 231)
    label_value("Bill to", "[Institution legal name]<br/>[Billing address]<br/>[Designated email]  /  [Tax ID, if applicable]", M+266, 270, CW-266)
    rule(360)
    columns = [M+10, M+270, M+347, W-M-10]
    c.setFillColor(PALE)
    c.rect(M, H-408, CW, 30, fill=1, stroke=0)
    for label, x, right in [("Description", columns[0], False), ("Qty", columns[1], False),
                            ("Rate / INR", columns[2], False), ("Amount / INR", columns[3], True)]:
        text(label, x, 388, 8, "SemiBold", GREEN, right)
    text("OfflineQR institutional licence", columns[0], 424, 9.5, "SemiBold")
    text("[Plan]  /  [Licence period]", columns[0], 443, 8, color=PLACEHOLDER)
    for value, x, right in [("[Count]", columns[1], False), ("[Rate]", columns[2], False), ("[Amount]", columns[3], True)]:
        text(value, x, 428, 9, color=PLACEHOLDER, right=right)
    rule(471)
    text("Customization and implementation", columns[0], 487, 9.5, "SemiBold")
    text("[Agreed scope, if applicable]", columns[0], 506, 8, color=PLACEHOLDER)
    text("[Amount]", columns[3], 491, 9, color=PLACEHOLDER, right=True)
    rule(535)
    label_value("Commercial terms", "Licence term: [Agreed term]<br/>Payment terms: [Agreed terms]<br/>Delivery date: [Agreed date]", M, 555, 240)
    for top, label in [(553, "Subtotal"), (581, "Applicable tax"), (613, "Total payable")]:
        text(label, M+290, top, 9, "SemiBold" if top==613 else "Regular")
        text("[INR amount]", W-M, top, 10 if top==613 else 9,
             "Bold" if top==613 else "Regular", GREEN if top==613 else PLACEHOLDER, True)
    rule(604, M+290, CW-290)
    rule(654)
    text("Order and payment references", M, 672, 9, "SemiBold", GREEN)
    text("Payment ID: [Provider transaction ID]", M, 695, 8.5, color=PLACEHOLDER)
    text("Payment status: [Pending / verified]", M+266, 695, 8.5, color=PLACEHOLDER)
    text("Provider order ID: [Provider order reference]", M, 716, 8.5, color=PLACEHOLDER)
    text("Receipt reference: [Verified receipt ID]", M+266, 716, 8.5, color=PLACEHOLDER)
    paragraph("Payment references require verification. Secure access is delivered separately after approval; no credentials or activation secrets appear in this document.", 744, size=7.6, color=MUTED, leading=11)
    c.save()


with TemporaryDirectory(prefix="offlineqr-fonts-") as temp:
    source = ROOT / "faculty-portal/node_modules/@fontsource-variable/manrope/files/manrope-latin-wght-normal.woff2"
    for name, weight in [("Regular", 400), ("SemiBold", 600), ("Bold", 700)]:
        font = instantiateVariableFont(FontFile(source), {"wght": weight}, inplace=False)
        font.flavor = None
        for name_id, value in [(1, "Manrope"), (2, name), (4, f"Manrope {name}"), (6, f"Manrope-{name}")]:
            font["name"].setName(value, name_id, 3, 1, 0x409)
            font["name"].setName(value, name_id, 1, 0, 0)
        target = Path(temp) / f"Manrope{name}.ttf"
        font.save(target)
        pdfmetrics.registerFont(TTFont(f"Manrope{name}", str(target)))
    generate()

reader = PdfReader(OUTPUT)
assert len(reader.pages) == 2
assert not reader.get_fields()
assert all("OfflineQR" in page.extract_text() for page in reader.pages)
print(f"Created {OUTPUT}: 2 pages, vector brand mark, embedded Manrope typography")
