from pathlib import Path

from docx import Document
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_CELL_VERTICAL_ALIGNMENT
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "docs" / "OfflineQR_Attendance_Hardening_Report.docx"
GREEN = RGBColor(38, 126, 75)
INK = RGBColor(25, 35, 30)
MUTED = RGBColor(92, 107, 99)
PALE_GREEN = "EAF5EE"
PALE_GRAY = "F3F6F4"


def shade(cell, fill: str) -> None:
    properties = cell._tc.get_or_add_tcPr()
    element = OxmlElement("w:shd")
    element.set(qn("w:fill"), fill)
    properties.append(element)


def set_cell_text(cell, text: str, *, bold=False, color=INK, size=9.5) -> None:
    cell.text = ""
    paragraph = cell.paragraphs[0]
    paragraph.paragraph_format.space_after = Pt(0)
    run = paragraph.add_run(text)
    run.bold = bold
    run.font.name = "Calibri"
    run._element.rPr.rFonts.set(qn("w:ascii"), "Calibri")
    run._element.rPr.rFonts.set(qn("w:hAnsi"), "Calibri")
    run.font.size = Pt(size)
    run.font.color.rgb = color
    cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER


def heading(doc, text: str, level=1) -> None:
    paragraph = doc.add_paragraph()
    paragraph.paragraph_format.space_before = Pt(16 if level == 1 else 10)
    paragraph.paragraph_format.space_after = Pt(6)
    run = paragraph.add_run(text)
    run.bold = True
    run.font.name = "Calibri"
    run._element.rPr.rFonts.set(qn("w:ascii"), "Calibri")
    run._element.rPr.rFonts.set(qn("w:hAnsi"), "Calibri")
    run.font.size = Pt(16 if level == 1 else 12.5)
    run.font.color.rgb = GREEN if level == 1 else INK


def paragraph(doc, text: str, *, bold_prefix: str | None = None) -> None:
    item = doc.add_paragraph()
    item.paragraph_format.space_after = Pt(6)
    item.paragraph_format.line_spacing = 1.15
    if bold_prefix and text.startswith(bold_prefix):
        run = item.add_run(bold_prefix)
        run.bold = True
        run.font.color.rgb = INK
        item.add_run(text[len(bold_prefix):])
    else:
        item.add_run(text)
    for run in item.runs:
        run.font.name = "Calibri"
        run._element.rPr.rFonts.set(qn("w:ascii"), "Calibri")
        run._element.rPr.rFonts.set(qn("w:hAnsi"), "Calibri")
        run.font.size = Pt(10.5)
        if run.font.color.rgb is None:
            run.font.color.rgb = INK


def bullet(doc, text: str) -> None:
    item = doc.add_paragraph(style="List Bullet")
    item.paragraph_format.space_after = Pt(3)
    item.paragraph_format.line_spacing = 1.1
    run = item.add_run(text)
    run.font.name = "Calibri"
    run.font.size = Pt(10.5)
    run.font.color.rgb = INK


def table(doc, headers: list[str], rows: list[list[str]]) -> None:
    result = doc.add_table(rows=1, cols=len(headers))
    result.alignment = WD_TABLE_ALIGNMENT.CENTER
    result.style = "Table Grid"
    for index, value in enumerate(headers):
        shade(result.rows[0].cells[index], "DCEFE3")
        set_cell_text(result.rows[0].cells[index], value, bold=True, color=GREEN)
    for row_index, values in enumerate(rows):
        cells = result.add_row().cells
        for index, value in enumerate(values):
            if row_index % 2:
                shade(cells[index], PALE_GRAY)
            set_cell_text(cells[index], value)
    doc.add_paragraph().paragraph_format.space_after = Pt(2)


def build() -> None:
    doc = Document()
    section = doc.sections[0]
    section.top_margin = Inches(0.78)
    section.bottom_margin = Inches(0.72)
    section.left_margin = Inches(0.82)
    section.right_margin = Inches(0.82)

    styles = doc.styles
    styles["Normal"].font.name = "Calibri"
    styles["Normal"]._element.rPr.rFonts.set(qn("w:ascii"), "Calibri")
    styles["Normal"]._element.rPr.rFonts.set(qn("w:hAnsi"), "Calibri")
    styles["Normal"].font.size = Pt(10.5)

    cover = doc.add_paragraph()
    cover.alignment = WD_ALIGN_PARAGRAPH.CENTER
    cover.paragraph_format.space_before = Pt(66)
    cover.paragraph_format.space_after = Pt(8)
    run = cover.add_run("OFFLINEQR ATTENDANCE")
    run.bold = True
    run.font.name = "Calibri"
    run.font.size = Pt(28)
    run.font.color.rgb = GREEN

    subtitle = doc.add_paragraph()
    subtitle.alignment = WD_ALIGN_PARAGRAPH.CENTER
    subtitle.paragraph_format.space_after = Pt(22)
    run = subtitle.add_run("Security Hardening and Operational Architecture Report")
    run.font.name = "Calibri"
    run.font.size = Pt(16)
    run.font.color.rgb = INK

    summary = doc.add_table(rows=4, cols=2)
    summary.alignment = WD_TABLE_ALIGNMENT.CENTER
    summary.style = "Table Grid"
    summary_rows = [
        ("System", "Dynamic QR based Offline Attendance System for Institutions"),
        ("Scope", "Student Flutter app, Faculty Next.js portal, FastAPI backend, PostgreSQL protocol store"),
        ("Hardening focus", "Signed QR evidence, device-bound proofs, delayed reconciliation, controlled recovery, operational controls"),
        ("Report status", "Implementation and verification summary - 1 September 2026"),
    ]
    for row, (label, value) in zip(summary.rows, summary_rows):
        shade(row.cells[0], "DCEFE3")
        set_cell_text(row.cells[0], label, bold=True, color=GREEN)
        set_cell_text(row.cells[1], value)

    doc.add_page_break()
    heading(doc, "1. Executive Summary")
    paragraph(doc, "OfflineQR Attendance is designed so that a student can capture a signed attendance proof without internet access, preserve it locally, and synchronize it when the backend becomes reachable. The backend remains the authoritative institutional record and verifies every proof before it affects attendance.")
    paragraph(doc, "This hardening phase closes the main trust-boundary gaps discovered during implementation. In particular, the backend now verifies the signed QR artifact inside every offline proof, late proofs are reconciled only through a controlled session window, and a proof can no longer be silently re-signed by a replacement device.")
    heading(doc, "2. Operating Model")
    table(doc, ["Stage", "What happens", "Authority"], [
        ["Prepare", "Faculty starts a session; the roster is snapshotted and a session authorization is signed by the institution.", "Backend"],
        ["Capture", "The portal rotates a signed QR every five seconds. The app verifies the institution and session signatures before creating a device-signed claim.", "Student device"],
        ["Store", "Claim and proof are written atomically to the local outbox before any network call; their signing key remains in platform secure storage.", "Student device"],
        ["Reconcile", "The app foreground-polls every five seconds and submits pending proofs as soon as the backend is reachable.", "Backend"],
        ["Finalize", "A closed session enters SYNCING for seven days, then can be sealed as RECONCILED after delayed proofs are accepted or reviewed.", "Faculty + backend"],
    ])
    heading(doc, "3. QR and Proof Security")
    bullet(doc, "Every QR contains a session identifier, epoch, five-second issuance window, deterministic challenge, key identifier, signature, and institution-signed session authorization.")
    bullet(doc, "The server independently recomputes the expected epoch, issued/expires window, and challenge; it then verifies the QR signature with the session public key.")
    bullet(doc, "The QR evidence is embedded in the device-signed claim and stored in PostgreSQL. Replacing the QR challenge or signature invalidates the proof before an attendance record is written.")
    bullet(doc, "The student claim is limited to a 60-second post-scan processing window. The five-second QR and 60-second claim window remain separate controls.")
    heading(doc, "4. Hardening Controls Implemented")
    table(doc, ["Risk", "Control now implemented", "Verification"], [
        ["Forged QR in offline proof", "QR issued/expires/signature are persisted and reverified server-side against the signed session authorization.", "Tampered QR regression test"],
        ["Valid scan lost after faculty closes", "Session moves ACTIVE -> SYNCING and accepts eligible pre-close QR evidence for seven days.", "Late reconciliation regression test"],
        ["Proof rebound after device replacement", "Client no longer mutates or re-signs rejected proofs. Server accepts a revoked device only if its signed QR evidence predates revocation.", "Protocol review + unit coverage"],
        ["Duplicate attendance", "Database uniqueness constrains session/student and session/device; proof submissions are idempotent.", "Repeat-submit test"],
        ["Attestation misuse", "Attestation is roster-bound, session-state-bound, reason-whitelisted, and auditable as FACULTY_ATTESTATION.", "API validation"],
        ["Unaudited recovery", "Device replacement approval is guarded by a dedicated ICT credential and records the approving operator.", "Endpoint policy"],
        ["Abuse and opaque failures", "Sliding-window API limits, correlation IDs, structured API errors, and hardened response headers are active.", "Automated integration checks"],
        ["Offline state loss", "Claims, local proof records, and outbox entries are committed locally before sync; restart persistence is tested.", "Flutter restart test"],
        ["Roster drift", "Attendance sessions snapshot student eligibility at creation and never re-evaluate membership at late sync time.", "Database constraints"],
        ["Unverified releases", "CI rebuilds the database from migrations, runs backend/portal/app checks, and container-builds both services.", "GitHub Actions"],
    ])
    heading(doc, "5. Session Lifecycle")
    paragraph(doc, "CREATED represents a scheduled session. ACTIVE is the only state that can issue new QR codes. When faculty ends attendance, the session transitions to SYNCING: no new QR is issued, but proofs with a valid previously signed QR may still reconcile. After the seven-day reconciliation period, an authorized faculty workflow can seal the session as RECONCILED. The academic statuses stay intentionally simple: PRESENT or ABSENT.")
    heading(doc, "6. Faculty and Student Experience")
    table(doc, ["Surface", "Role in the system", "Offline behavior"], [
        ["Flutter student app", "Shows timetable, personal attendance, scanner, and Institution portal links.", "Reads local timetable/history and stores signed proof outbox entries without internet."],
        ["Faculty Next.js portal", "Shows assigned classes, live roster, dynamic QR, manual attestation, records, and projector mode.", "Keeps cached session/roster state; an institution deployment should use a managed classroom host for long-duration offline signing."],
        ["FastAPI backend", "Verifies signatures, eligibility, device status at scan time, duplicates, records, and audit events.", "Authoritative once reachable; accepts eligible delayed evidence during the reconciliation window."],
    ])
    heading(doc, "7. CI/CD and Release Gates")
    bullet(doc, "Continuous Integration runs on pull requests and main-branch pushes: fresh PostgreSQL migration rebuild, SQL checks, Python protocol tests, Flutter analysis/tests, Next.js tests/build, dependency audits, and Docker image builds.")
    bullet(doc, "Release Containers triggers only on version tags. It publishes versioned backend and faculty portal images to GitHub Container Registry using GitHub's scoped token.")
    bullet(doc, "A release is blocked by failed migrations, signature/late-sync regressions, failed app analysis, failed frontend build, or container build failure.")
    heading(doc, "8. Deployment Requirements")
    paragraph(doc, "The repository is production-hardened at the code boundary, but institutional deployment still needs real identity infrastructure and operations. These are required controls, not optional polish.")
    bullet(doc, "Replace development identity headers and the demonstration password with Institution OIDC/Google Workspace sign-in, role claims, and server-side session tokens.")
    bullet(doc, "Store institution signing seeds and ICT approval credentials only in a managed secrets service. Production startup already fails when default signing material or a weak ICT key is used.")
    bullet(doc, "Move rate limiting and session coordination to Redis, run PostgreSQL backups with restore drills, and centralize audit logs and alerts.")
    bullet(doc, "Use Android Play Integrity and Apple App Attest before claiming strong device integrity. Cryptographic keys alone cannot attest that an uncompromised handset produced the proof.")
    bullet(doc, "For true faculty-offline signing, deploy a managed native Attendance Host or secure hardware-backed classroom node. A browser cannot offer the same secret-storage guarantee as a native managed device.")
    heading(doc, "9. Residual Threat Position")
    paragraph(doc, "No attendance system can prevent a student from physically handing their enrolled phone to another person. OfflineQR Attendance is designed to reduce practical proxy routes: a rotating signed QR, one active device, encrypted local keys, eligibility snapshots, replay prevention, audit records, and faculty fallback all raise the cost of abuse and make disputes investigable. Physical collusion requires policy and human supervision in addition to software controls.")
    heading(doc, "10. Verification Summary")
    table(doc, ["Area", "Result"], [
        ["Database migrations and integrity checks", "Passed on a clean PostgreSQL rebuild"],
        ["Backend unit and protocol tests", "33 tests passed"],
        ["Faculty portal tests and Next.js production build", "Passed"],
        ["Flutter static analysis and unit tests", "No analysis issues; 22 tests passed"],
        ["CI/CD definitions", "Added for boundary testing, audit gates, container builds, and tagged image publishing"],
    ])

    footer = section.footer.paragraphs[0]
    footer.alignment = WD_ALIGN_PARAGRAPH.CENTER
    footer_run = footer.add_run("OfflineQR Attendance | Security Hardening Report")
    footer_run.font.name = "Calibri"
    footer_run.font.size = Pt(8)
    footer_run.font.color.rgb = MUTED

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    doc.save(OUTPUT)
    print(OUTPUT)


if __name__ == "__main__":
    build()
