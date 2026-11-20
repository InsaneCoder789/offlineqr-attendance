from __future__ import annotations

from pathlib import Path
from datetime import date
from textwrap import wrap
from PIL import Image, ImageDraw, ImageFont
from docx import Document
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.section import WD_SECTION
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_CELL_VERTICAL_ALIGNMENT
from docx.oxml import OxmlElement
from docx.oxml.ns import qn

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "Dynamic_QR_Offline_Attendance_System_SRS.docx"
ASSET = ROOT / ".srs_assets"
ASSET.mkdir(exist_ok=True)

NAVY = "#17365D"
GREEN = "#227A42"
PALE = "#F3F8F4"
LIGHT = "#E8EEE9"
MID = "#5E6B64"
INK = "#111827"


def font(size, bold=False):
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
    ]
    for path in candidates:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def diagram(name, title, subtitle, lanes, edges):
    """Create a high-resolution visual rendering of the corresponding Mermaid flow."""
    W, H = 2200, 1500
    im = Image.new("RGB", (W, H), "white")
    draw = ImageDraw.Draw(im)
    draw.rectangle((0, 0, W, 150), fill=NAVY)
    draw.text((80, 38), title, font=font(50, True), fill="white")
    draw.text((82, 96), subtitle, font=font(24), fill="#D7E2EE")
    positions = {}
    cols = max(len(lanes), 1)
    lane_w = (W - 180) // cols
    for c, lane in enumerate(lanes):
        x = 90 + c * lane_w
        draw.rounded_rectangle((x, 205, x + lane_w - 25, 1320), radius=24, fill=PALE, outline="#D5E4DA", width=3)
        draw.text((x + 34, 235), lane[0], font=font(28, True), fill=GREEN)
        boxes = lane[1]
        usable = 960
        step = usable // max(len(boxes), 1)
        for r, (key, text) in enumerate(boxes):
            y = 315 + r * step
            bx = (x + 38, y, x + lane_w - 63, y + 135)
            positions[key] = bx
            draw.rounded_rectangle(bx, radius=20, fill="white", outline="#AEC4B4", width=3)
            tx = bx[0] + 26
            lines = wrap(text, width=22)
            ty = bx[1] + (135 - len(lines) * 30) // 2
            for line in lines:
                draw.text((tx, ty), line, font=font(28, True), fill=INK)
                ty += 34
    for source, target, label in edges:
        sx1, sy1, sx2, sy2 = positions[source]
        tx1, ty1, tx2, ty2 = positions[target]
        # Orthogonal connectors keep the print layout legible; the complete flow logic remains in Mermaid source.
        source_center = ((sx1 + sx2) // 2, (sy1 + sy2) // 2)
        target_center = ((tx1 + tx2) // 2, (ty1 + ty2) // 2)
        if abs(source_center[0] - target_center[0]) < 80:
            start = ((sx1 + sx2) // 2, sy2)
            end = ((tx1 + tx2) // 2, ty1)
            points = [start, end]
        else:
            moving_right = source_center[0] < target_center[0]
            start = (sx2 if moving_right else sx1, source_center[1])
            end = (tx1 if moving_right else tx2, target_center[1])
            mid_x = (start[0] + end[0]) // 2
            points = [start, (mid_x, start[1]), (mid_x, end[1]), end]
        draw.line(points, fill=GREEN, width=5, joint="curve")
        x, y = end
        if abs(points[-2][0] - end[0]) > abs(points[-2][1] - end[1]):
            direction = -1 if points[-2][0] < end[0] else 1
            draw.polygon([(x, y), (x + 15 * direction, y - 10), (x + 15 * direction, y + 10)], fill=GREEN)
        else:
            direction = -1 if points[-2][1] < end[1] else 1
            draw.polygon([(x, y), (x - 10, y + 15 * direction), (x + 10, y + 15 * direction)], fill=GREEN)
        if label:
            mx, my = points[len(points) // 2]
            draw.rounded_rectangle((mx - 75, my - 18, mx + 75, my + 19), radius=10, fill="white")
            draw.text((mx - 65, my - 11), label, font=font(17), fill=MID)
    draw.line((80, 1410, W - 80, 1410), fill="#D9E2DD", width=2)
    draw.text((82, 1432), "Structured architecture view derived from the accompanying Mermaid source.", font=font(22), fill=MID)
    output = ASSET / f"{name}.png"
    im.save(output)
    return output


def shade(cell, color):
    tcPr = cell._tc.get_or_add_tcPr()
    shd = tcPr.find(qn("w:shd"))
    if shd is None:
        shd = OxmlElement("w:shd")
        tcPr.append(shd)
    shd.set(qn("w:fill"), color)


def cell_margin(cell, top=110, start=120, bottom=110, end=120):
    tc = cell._tc
    tcPr = tc.get_or_add_tcPr()
    mar = tcPr.first_child_found_in("w:tcMar")
    if mar is None:
        mar = OxmlElement("w:tcMar")
        tcPr.append(mar)
    for side, value in (("top", top), ("start", start), ("bottom", bottom), ("end", end)):
        node = mar.find(qn(f"w:{side}"))
        if node is None:
            node = OxmlElement(f"w:{side}")
            mar.append(node)
        node.set(qn("w:w"), str(value))
        node.set(qn("w:type"), "dxa")


def set_repeat_table_header(row):
    trPr = row._tr.get_or_add_trPr()
    tblHeader = OxmlElement("w:tblHeader")
    tblHeader.set(qn("w:val"), "true")
    trPr.append(tblHeader)


def keep_with_next(paragraph):
    pPr = paragraph._p.get_or_add_pPr()
    el = OxmlElement("w:keepNext")
    pPr.append(el)


def add_page_number(paragraph):
    paragraph.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    run = paragraph.add_run("Page ")
    run.font.size = Pt(8)
    fld = OxmlElement("w:fldSimple")
    fld.set(qn("w:instr"), "PAGE")
    paragraph._p.append(fld)


def add_text(p, text, size=11, bold=False, color=INK, italic=False):
    r = p.add_run(text)
    r.bold = bold
    r.italic = italic
    r.font.name = "Aptos"
    r.font.size = Pt(size)
    r.font.color.rgb = RGBColor.from_string(color.replace("#", ""))
    return r


def para(doc, text="", style=None, before=0, after=7, align=None):
    p = doc.add_paragraph(style=style)
    p.paragraph_format.space_before = Pt(before)
    p.paragraph_format.space_after = Pt(after)
    p.paragraph_format.line_spacing = 1.15
    if align is not None:
        p.alignment = align
    if text:
        add_text(p, text)
    return p


def heading(doc, text, level=1):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(14 if level == 1 else 9)
    p.paragraph_format.space_after = Pt(6)
    keep_with_next(p)
    add_text(p, text, 16 if level == 1 else 12, bold=True, color="000000")
    return p


def table(doc, headers, rows, widths=None):
    t = doc.add_table(rows=1, cols=len(headers))
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    t.style = "Table Grid"
    hdr = t.rows[0]
    set_repeat_table_header(hdr)
    for i, h in enumerate(headers):
        c = hdr.cells[i]
        shade(c, NAVY)
        cell_margin(c)
        c.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
        p = c.paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        add_text(p, h, 9, True, "FFFFFF")
        if widths:
            c.width = Inches(widths[i])
    for n, row in enumerate(rows):
        cells = t.add_row().cells
        for i, value in enumerate(row):
            c = cells[i]
            shade(c, "F6F8F7" if n % 2 else "FFFFFF")
            cell_margin(c)
            c.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
            p = c.paragraphs[0]
            add_text(p, str(value), 9.2, False, INK)
            if widths:
                c.width = Inches(widths[i])
    doc.add_paragraph().paragraph_format.space_after = Pt(2)
    return t


def bullet(doc, text):
    p = doc.add_paragraph(style="List Bullet")
    p.paragraph_format.space_after = Pt(3)
    p.paragraph_format.line_spacing = 1.1
    add_text(p, text, 10.5)
    return p


def diagram_page(doc, number, title, description, image, source_name):
    heading(doc, f"{number} {title}")
    p = para(doc, description, after=10)
    p.paragraph_format.line_spacing = 1.12
    doc.add_picture(str(image), width=Inches(6.95))
    cap = para(doc, f"Figure {number}. Structured architecture view derived from the Mermaid source in architecture_mermaid.md: {source_name}.", after=0, align=WD_ALIGN_PARAGRAPH.CENTER)
    for r in cap.runs:
        r.font.size = Pt(8.5)
        r.italic = True
        r.font.color.rgb = RGBColor.from_string(MID.replace("#", ""))
    doc.add_page_break()


def add_requirement_table(doc, title, items):
    heading(doc, title, 2)
    table(doc, ["ID", "Requirement"], items, [1.0, 5.9])


def main():
    mobile = diagram(
        "mobile_architecture", "Student Mobile Application", "Flutter client, device-bound proof, local-first persistence and eventual synchronization",
        [
            ("Student", [("m1", "Student sign in"), ("m2", "Scan live classroom QR"), ("m3", "See attendance and timetable")]),
            ("Flutter Mobile App", [("m4", "Roll number password session"), ("m5", "QR validation and device signing"), ("m6", "Local SQLite record and outbox"), ("m7", "Poll and sync when reachable")]),
            ("Institutional Services", [("m8", "Attendance protocol API"), ("m9", "Server verification and receipt")]),
        ], [("m1","m4","login"),("m4","m5","authorise"),("m5","m6","proof"),("m6","m7","queue"),("m7","m8","sync"),("m8","m9","verify")])
    faculty = diagram(
        "faculty_architecture", "Faculty Portal", "Next.js portal, signed QR creation, live roster and human exception handling",
        [
            ("Faculty", [("f1", "Institution faculty sign in"), ("f2", "Start attendance"), ("f3", "Review roster or attest")]),
            ("Faculty Portal", [("f4", "Dashboard and scheduled classes"), ("f5", "Projector QR display"), ("f6", "Live roster WebSocket"), ("f7", "Records and session history")]),
            ("Protocol Services", [("f8", "Session and QR authorisation"), ("f9", "PostgreSQL authority"), ("f10", "Redis events and limits")]),
        ], [("f1","f4","session"),("f4","f8","create"),("f8","f5","QR epoch"),("f5","f6","proofs"),("f6","f10","events"),("f10","f9","persist"),("f3","f7","review")])
    ict = diagram(
        "ict_architecture", "ICT Administration Portal", "Role-protected device governance, password recovery and auditable replacement activation",
        [
            ("ICT Administrator", [("i1", "Role protected sign in"), ("i2", "Search roll number"), ("i3", "Approve or reject request")]),
            ("ICT Portal", [("i4", "Device history and status"), ("i5", "Issue one-use activation QR"), ("i6", "Password recovery controls"), ("i7", "Audit review")]),
            ("Authoritative Services", [("i8", "Administrative API"), ("i9", "Atomic replacement workflow"), ("i10", "PostgreSQL audit trail")]),
        ], [("i1","i4","access"),("i2","i4","lookup"),("i3","i5","approved"),("i5","i8","token"),("i8","i9","consume"),("i9","i10","audit"),("i6","i8","reset"),("i10","i7","review")])
    context = diagram(
        "system_context", "Connected System Context", "Independent client roles share a protocol service without requiring Internet at the moment of capture",
        [
            ("Classroom", [("c1", "Faculty QR display"), ("c2", "Student in-app scanner"), ("c3", "Local proof outbox")]),
            ("Platform", [("c4", "FastAPI verification service"), ("c5", "PostgreSQL attendance authority"), ("c6", "Redis coordination and event stream")]),
            ("Governance", [("c7", "Faculty live roster"), ("c8", "ICT device governance"), ("c9", "Audit and reporting")]),
        ], [("c1","c2","visible QR"),("c2","c3","capture"),("c3","c4","when online"),("c4","c5","record"),("c4","c6","publish"),("c6","c7","update"),("c8","c4","govern"),("c5","c9","report")])

    doc = Document()
    section = doc.sections[0]
    section.page_width, section.page_height = Inches(8.5), Inches(11)
    section.top_margin, section.bottom_margin = Inches(0.68), Inches(0.65)
    section.left_margin, section.right_margin = Inches(0.75), Inches(0.75)
    styles = doc.styles
    styles["Normal"].font.name = "Aptos"
    styles["Normal"].font.size = Pt(10.5)
    styles["Normal"].font.color.rgb = RGBColor.from_string(INK.replace("#", ""))
    for s in ["Title", "Heading 1", "Heading 2", "Heading 3"]:
        styles[s].font.name = "Aptos"
        styles[s].font.color.rgb = RGBColor(0, 0, 0)
    header = section.header.paragraphs[0]
    header.alignment = WD_ALIGN_PARAGRAPH.CENTER
    add_text(header, "DYNAMIC QR BASED OFFLINE ATTENDANCE SYSTEM FOR INSTITUTIONS", 8.5, True, NAVY)
    footer = section.footer.paragraphs[0]
    add_page_number(footer)

    # Cover page
    p = para(doc, before=5, after=8, align=WD_ALIGN_PARAGRAPH.CENTER)
    add_text(p, "SOFTWARE ENGINEERING PROJECT MANUAL", 11, True, NAVY)
    p = para(doc, after=45, align=WD_ALIGN_PARAGRAPH.CENTER)
    add_text(p, "Dynamic QR Based Offline\nAttendance System for Institutions", 27, True, "000000")
    p = para(doc, after=17, align=WD_ALIGN_PARAGRAPH.CENTER)
    add_text(p, "Software Requirements Specification and Detailed Design", 14, False, INK)
    p = para(doc, after=45, align=WD_ALIGN_PARAGRAPH.CENTER)
    add_text(p, "Student Mobile Application  Faculty Portal  ICT Device Governance", 11, False, MID)
    p = para(doc, after=8, align=WD_ALIGN_PARAGRAPH.CENTER)
    add_text(p, "Prepared for academic review and institutional evaluation", 10.5, False, MID)
    p = para(doc, after=8, align=WD_ALIGN_PARAGRAPH.CENTER)
    add_text(p, "OfflineQR", 12, True, "000000")
    p = para(doc, after=0, align=WD_ALIGN_PARAGRAPH.CENTER)
    add_text(p, "Institutional Attendance Platform", 11, False, INK)
    p = para(doc, before=42, after=0, align=WD_ALIGN_PARAGRAPH.CENTER)
    add_text(p, "Version 1.0  |  5 September 2026", 10, True, NAVY)
    doc.add_page_break()

    # Document control and contents
    heading(doc, "Document Control")
    para(doc, "This Software Requirements Specification defines the behaviour, constraints and verification baseline for the Dynamic QR Based Offline Attendance System for Institutions. It is intended for evaluators, institutional stakeholders, developers and test reviewers.")
    table(doc, ["Field", "Value"], [
        ("Document title", "Dynamic QR Based Offline Attendance System for Institutions"),
        ("Document type", "Software Requirements Specification and Detailed Design"),
        ("Version", "1.0"),
        ("Status", "Submission baseline"),
        ("Classification", "Institutional project documentation"),
        ("Date", "5 September 2026"),
    ], [1.75, 5.15])
    heading(doc, "Revision History", 2)
    table(doc, ["Version", "Date", "Description"], [("1.0", "5 September 2026", "Initial SRS covering the student app, faculty portal, ICT portal, protocol, offline operation and control requirements.")], [1.0, 1.4, 4.5])
    heading(doc, "Contents", 2)
    for item in [
        "1 Introduction", "2 Overall Description", "3 Architecture and System Context", "4 Functional Requirements", "5 Attendance and Device Protocols", "6 Data and Interface Requirements", "7 Non Functional Requirements", "8 Exception Handling and Recovery", "9 Verification and Acceptance Criteria", "10 Assumptions and Future Controls", "Appendix A Mermaid Diagram Source", "Appendix B Glossary",
    ]:
        p = para(doc, item, after=2)
        add_text(p, "", 10.5)
    doc.add_page_break()

    heading(doc, "1 Introduction")
    heading(doc, "1.1 Purpose", 2)
    para(doc, "The system provides an attendance workflow that remains usable when classroom Internet connectivity is unavailable. A student captures an attendance proof on a registered mobile device, stores it durably on that device, and synchronizes it when the institutional service becomes reachable. The backend remains the final authority for eligibility, device status, replay prevention, duplicate prevention and institutional reporting.")
    heading(doc, "1.2 Scope", 2)
    para(doc, "The product includes a Flutter student application, a Next.js faculty portal, a Next.js ICT administration portal, a FastAPI protocol service, PostgreSQL as the authoritative data store and Redis for short-lived coordination, rate limiting and event delivery. The scope covers academic attendance, device governance, auditability and recovery workflows. It does not claim to eliminate physical collusion, such as deliberate lending of a registered phone.")
    heading(doc, "1.3 Document Conventions", 2)
    table(doc, ["Convention", "Meaning"], [
        ("FR", "Functional requirement identifier"),
        ("NFR", "Non-functional requirement identifier"),
        ("MUST", "Mandatory behaviour for an accepted implementation"),
        ("SHOULD", "Preferred behaviour that may require institutional rollout support"),
        ("Technical state", "Synchronization or verification information that does not replace PRESENT or ABSENT"),
    ], [1.65, 5.25])
    heading(doc, "1.4 Definitions", 2)
    bullet(doc, "Attendance session: one independently identified lecture attendance event created by a faculty member.")
    bullet(doc, "QR epoch: a signed QR challenge displayed for five seconds during an active attendance session.")
    bullet(doc, "Attendance proof: a signed, locally stored statement of a successful scan created by the registered device.")
    bullet(doc, "Activation QR: a one-use, time-limited QR issued by ICT after a device replacement request is approved.")
    doc.add_page_break()

    heading(doc, "2 Overall Description")
    heading(doc, "2.1 Product Perspective", 2)
    para(doc, "The platform separates client experience, attendance protocol processing, device governance and authoritative record keeping. This separation is essential: the student client can capture a proof locally, the faculty interface can coordinate an active classroom session, and only the backend can finalize the institutional record. Redis carries short-lived coordination state; PostgreSQL retains the authoritative academic and audit history.")
    heading(doc, "2.2 User Classes", 2)
    table(doc, ["User class", "Primary responsibility", "Access boundary"], [
        ("Student", "View timetable and attendance, sign in, register a device and scan an attendance QR.", "Only the student’s own identity, device and attendance history."),
        ("Faculty member", "View assigned classes, start attendance, review roster, attest exceptional cases and inspect records.", "Only assigned courses, sections and sessions."),
        ("ICT administrator", "Govern device registration, approve replacement, reset credentials and review audit history.", "Role-protected administrative controls."),
        ("Backend service", "Verify protocol claims, enforce authoritative rules and publish updates.", "No direct human UI access."),
    ], [1.25, 3.0, 2.65])
    heading(doc, "2.3 Operating Principles", 2)
    bullet(doc, "Local-first capture: a valid proof is written to the mobile database before a network request is attempted.")
    bullet(doc, "One active attendance device per student: the backend device registry is authoritative; reinstalling an app does not create a new approved device.")
    bullet(doc, "Short-lived QR evidence: a visible QR rotates every five seconds; a scan taken during its epoch establishes a limited claim-processing window.")
    bullet(doc, "Human fallback: faculty attestation retains a recorded, auditable route for exceptional cases.")
    doc.add_page_break()

    heading(doc, "3 Architecture and System Context")
    para(doc, "The next four pages show the requested architectures separately. In each view the visual occupies the majority of the page; the short narrative explains the boundary, responsibilities and trust decision represented by that diagram.")
    doc.add_page_break()
    diagram_page(doc, "3.1", "Student Mobile Application Architecture", "The student application is a native Flutter client for Android and iOS. It manages student sign-in, device-bound key material held by platform secure storage, QR validation, durable proof storage, an outbox and retry polling. Timetable and attendance history remain available from local data when the backend is unavailable. No private device key is exported through a QR transfer process.", mobile, "Student Mobile Application")
    diagram_page(doc, "3.2", "Faculty Portal Architecture", "The faculty portal is a dedicated Next.js application with separate dashboards, class, attendance and records views. Starting a session asks the backend to authorize an active session and issue signed QR epochs. The portal receives roster updates from the backend event path and retains faculty attestation as a controlled exception path.", faculty, "Faculty Portal")
    diagram_page(doc, "3.3", "ICT Administration Portal Architecture", "The ICT portal uses role-protected administrative APIs rather than client-side device changes. ICT can inspect device history, review a replacement request and issue a short-lived, one-use activation QR only after approval. Consuming the activation performs the device switch atomically and leaves an audit event.", ict, "ICT Administration Portal")
    diagram_page(doc, "3.4", "Connected System Context", "The classroom QR is a visible challenge from the faculty session, while the student app is the only normal capture path. Internet failure does not prevent durable local proof creation. When connectivity returns, the client synchronizes with the protocol service; after server verification, PostgreSQL is updated and Redis publishes a roster update for the faculty portal.", context, "Connected System Context")

    heading(doc, "4 Functional Requirements")
    para(doc, "The following requirements are testable behaviours. Academic attendance is represented as PRESENT or ABSENT. Sync states such as pending, accepted or rejected are technical metadata and must not create separate academic states.")
    add_requirement_table(doc, "4.1 Student Application", [
        ("FR S01", "The application MUST authenticate a student by roll number and password, issue a short-lived opaque session and require a password change when a temporary credential is used."),
        ("FR S02", "The application MUST generate and retain device signing material in platform secure storage. The private key MUST NOT be exported by the device transfer feature."),
        ("FR S03", "The application MUST display timetable, subject-wise attendance and local attendance history using locally synchronized data."),
        ("FR S04", "The scanner MUST accept attendance QR payloads only through the in-app attendance workflow and validate version, signature, session, epoch and payload bounds before creating a proof."),
        ("FR S05", "A successful scan MUST create one durable local proof containing a unique proof identifier, session reference, device reference, epoch evidence, nonce and device signature before any sync attempt."),
        ("FR S06", "The application MUST retry pending proofs after connectivity becomes available and update the local technical state from the server result."),
        ("FR S07", "The application MUST prevent multiple PRESENT records for the same student and attendance session in its local experience while retaining any server response for review."),
        ("FR S08", "The application MUST provide an attendance logger showing local capture time, claim state, synchronization attempts, server result and review code."),
    ])
    doc.add_page_break()

    add_requirement_table(doc, "4.2 Faculty Portal", [
        ("FR F01", "The portal MUST authenticate faculty members and constrain dashboard, class, roster and record data to their assigned institutional scope."),
        ("FR F02", "The portal MUST show today’s classes, next class, completed sessions, pending synchronization information and a direct start-attendance action."),
        ("FR F03", "Starting attendance MUST create or resume one authoritative attendance session and show course, section, room, QR refresh countdown and present count."),
        ("FR F04", "The live QR display MUST rotate every five seconds and be available in a high-contrast projector mode containing only session-identifying information needed by the classroom."),
        ("FR F05", "The roster MUST refresh after backend events and show the student attendance method, including DYNAMIC_QR or FACULTY_ATTESTATION."),
        ("FR F06", "Faculty MUST be able to attest a roster student with a reason, confirmation step, faculty identity and auditable timestamp."),
        ("FR F07", "The records view MUST support course, section and date filters, course-wise session history, student-wise register view and export-ready reporting."),
        ("FR F08", "Closing a session MUST retain server-side consideration for a proof captured within the permitted protocol window, subject to cryptographic and eligibility checks."),
    ])
    heading(doc, "4.3 ICT Administration Portal", 2)
    table(doc, ["ID", "Requirement"], [
        ("FR I01", "The portal MUST allow only authorized ICT roles to view device history, approve or reject replacement requests, revoke registrations and reset student credentials."),
        ("FR I02", "Device replacement MUST be approval-led. Approval creates no automatic active device; ICT must deliberately generate an activation QR for the approved candidate device."),
        ("FR I03", "An activation QR MUST be opaque, single-use, short-lived and bound to the approved replacement record. Its server representation MUST be hashed."),
        ("FR I04", "Activation consumption MUST atomically revoke the previous active device and activate the approved candidate device, then append an audit event."),
        ("FR I05", "The portal MUST expose device make, model, OS version and declared physical-device status only as administrative reference metadata. It MUST NOT expose raw identifiers to students or treat declared metadata as conclusive anti-emulator evidence."),
    ], [1.0, 5.9])
    doc.add_page_break()

    heading(doc, "5 Attendance and Device Protocols")
    heading(doc, "5.1 Dynamic QR Attendance Lifecycle", 2)
    para(doc, "A faculty member starts an attendance session. The service authorizes a QR epoch containing protocol version, session identifier, epoch number, issue time, expiry time, unpredictable challenge and server signature. The QR visible on the display changes every five seconds. The scanner must read and validate a QR during the epoch in which it is shown. That valid scan establishes a limited claim-processing window of approximately sixty seconds; it does not make an expired, unscanned QR reusable.")
    table(doc, ["Step", "Required control", "Outcome"], [
        ("1", "Faculty starts an authorized session.", "A unique session is active."),
        ("2", "Service signs a QR epoch with a five-second display lifetime.", "Screenshots become short-lived evidence."),
        ("3", "Student scans within the QR epoch using the application scanner.", "Client validates the public challenge and session context."),
        ("4", "Student device signs and persists the proof locally.", "Capture survives lost Internet connectivity."),
        ("5", "Backend checks session, eligibility, device status, QR validity, signature and duplicates.", "Accepted proof becomes a PRESENT record; rejected proof remains reviewable."),
    ], [0.55, 3.0, 3.35])
    heading(doc, "5.2 Offline Synchronization and Reconciliation", 2)
    para(doc, "The client never waits for the Internet before confirming a durable local capture. The outbox records pending work, retries with bounded backoff and polls after connectivity returns. The backend performs the same verification regardless of whether a proof arrived immediately or later. On acceptance it writes the authoritative record, emits a Redis event and the faculty portal refreshes the active roster. A rejected proof is not silently discarded: its reason and attempts remain in the student logger and faculty-facing review state.")
    heading(doc, "5.3 Device Binding and Replacement", 2)
    para(doc, "A student can have one active attendance device. Registration binds a public signing key to the student; the private key remains on the phone. A lost or replaced phone is handled through ICT governance, not account logout or transfer of a private key. The student requests replacement, ICT approves the candidate, ICT creates a five-minute one-use activation QR, and the new authenticated phone consumes it. Server-side activation revokes the old device and produces an audit record in one transaction.")
    doc.add_page_break()

    heading(doc, "6 Data and Interface Requirements")
    heading(doc, "6.1 Authoritative Data Entities", 2)
    table(doc, ["Entity", "Purpose", "Authority"], [
        ("Student and enrolment", "Roll number, section and course eligibility.", "PostgreSQL institutional record."),
        ("Student credential", "Argon2id password hash, temporary-password flag, lockout counters.", "PostgreSQL; plaintext passwords are never retained."),
        ("Device registration", "Public key, status, activation/revocation state and minimal device reference metadata.", "PostgreSQL device registry."),
        ("Attendance session", "Course, section, faculty, room, lifecycle and QR signing context.", "PostgreSQL with Redis coordination."),
        ("Attendance proof", "Signed local claim and verification outcome.", "PostgreSQL after server acceptance; local SQLite before sync."),
        ("Faculty attestation", "Faculty-created exceptional PRESENT record and reason.", "PostgreSQL with audit event."),
        ("Audit event", "Security-sensitive administrative and attendance actions.", "Append-only institutional audit data."),
    ], [1.45, 3.1, 2.35])
    heading(doc, "6.2 Interface Boundaries", 2)
    table(doc, ["Interface", "Requirement"], [
        ("Student to backend", "HTTPS JSON API using opaque bearer session; production use must not accept development-only identity headers."),
        ("Faculty and ICT to backend", "HTTPS API protected by role-aware session cookies, CSRF protection and server-side authorization."),
        ("Backend to faculty portal", "WebSocket or equivalent event channel for active-roster changes, backed by Redis coordination and re-fetch confirmation."),
        ("Faculty display to student", "Optical QR only. Public QR payload contains no student identity."),
        ("Student local storage", "SQLite durable outbox and synchronized view data; device signing key held separately in platform secure storage."),
    ], [1.75, 5.15])
    heading(doc, "6.3 Data Minimization", 2)
    para(doc, "The system must not collect MAC addresses, IMEI, public IP address or unrestricted location solely for attendance. Device make, model, operating system version and declared physical-device status may be retained only for ICT support, audit correlation and policy investigation. Browser developer tools cannot be prevented from inspecting a browser client; the design therefore relies on server-side authorization and never places secrets, private keys, password values or administrative permissions in browser code.")
    doc.add_page_break()

    heading(doc, "7 Non Functional Requirements")
    table(doc, ["ID", "Requirement"], [
        ("NFR 01 Security", "Device private keys MUST remain in Android Keystore or iOS Keychain-backed storage. Server verification MUST use registered public keys and trust-root QR verification."),
        ("NFR 02 Authentication", "Student password verification MUST use Argon2id. Temporary credentials MUST force change before attendance use. Login failures MUST be rate-limited and lockable."),
        ("NFR 03 Availability", "A student proof capture MUST complete without Internet once local session and eligibility data are available. Server synchronization is eventual, not a prerequisite for capture."),
        ("NFR 04 Integrity", "The service MUST enforce unique session/student and session/device attendance records, reject replayed proof identifiers and validate signed payload bounds."),
        ("NFR 05 Performance", "QR epoch generation and roster event propagation SHOULD remain responsive for a classroom-scale section. Redis is used for shared session coordination, rate limits and event fan-out rather than as the attendance authority."),
        ("NFR 06 Compatibility", "Android support floor is API 23 and iOS support floor is iOS 12. Devices below these floors are not supported because secure storage and modern transport controls cannot be assured."),
        ("NFR 07 Privacy", "Student identities MUST NOT be embedded in public QR payloads. The minimum required institutional data is retained, and audit access is role-scoped."),
        ("NFR 08 Observability", "Protocol acceptance, rejection, synchronization and device governance actions MUST create auditable events without logging passwords or private cryptographic material."),
        ("NFR 09 Resilience", "Client outboxes MUST recover interrupted synchronization attempts; portal pages MUST represent offline, empty, rejected and unavailable states clearly."),
        ("NFR 10 Deployment", "Android updates may use a signed manifest and HTTPS-hosted APK with user-confirmed installation. iOS public updates require an approved Apple distribution route such as App Store, TestFlight, MDM or enterprise distribution."),
    ], [1.0, 5.9])
    doc.add_page_break()

    heading(doc, "8 Exception Handling and Recovery")
    table(doc, ["Condition", "Required response"], [
        ("Internet unavailable during scan", "Persist the signed proof locally, show captured/pending technical state and retry after connectivity returns."),
        ("QR scanned outside epoch", "Reject before proof creation, explain that the QR changed and invite a current in-app scan."),
        ("Student not enrolled in session", "Reject with no academic status change; retain minimal diagnostic result for review."),
        ("Duplicate attendance scan", "Show that attendance for the session is already recorded; do not create another academic record."),
        ("Device revoked or replaced", "Reject proof server-side, retain the client log and direct the student to ICT replacement process."),
        ("Faculty device or scanner failure", "Faculty uses roster search and a reasoned attestation, recorded as FACULTY_ATTESTATION."),
        ("Backend unavailable to faculty", "The portal preserves locally available session context and clearly indicates degraded mode. Full offline faculty hosting requires deployment validation of local session persistence and later reconciliation."),
        ("Activation QR expired or consumed", "Reject activation atomically; ICT generates a new QR only after reviewing the request state."),
    ], [2.1, 4.8])
    heading(doc, "8.1 Security Limitations", 2)
    para(doc, "No software-only attendance system can prove that the person carrying a registered phone is its enrolled owner. The design substantially raises the effort for casual proxy attendance by combining a short-lived QR, registered device key, eligibility checks, duplicate rules, server re-verification and an auditable device lifecycle. For a higher assurance rollout, the institution should add platform attestation such as Play Integrity and App Attest, MDM policy where available, staff data onboarding controls and formal incident response procedures.")
    doc.add_page_break()

    heading(doc, "9 Verification and Acceptance Criteria")
    table(doc, ["Area", "Acceptance criterion"], [
        ("QR protocol", "A valid five-second epoch produces a proof only when scanned during that epoch. A previously displayed but unscanned payload is rejected after expiry."),
        ("Local-first capture", "With network disabled after bootstrap, a valid scan creates a durable local proof and a visible pending entry in the attendance logger."),
        ("Eventual sync", "After connectivity returns, a pending proof is submitted, verified once, recorded in PostgreSQL and reflected in the faculty roster through event refresh."),
        ("Duplicate control", "Repeated scans by one student for one session retain one academic attendance record and return an understandable already-recorded result."),
        ("Device replacement", "A student cannot self-activate a second device. After ICT approval, only a single-use unexpired activation QR can atomically switch the active device."),
        ("Faculty exception", "A faculty attestation records faculty identity, student, reason, timestamp, session and FACULTY_ATTESTATION method."),
        ("Authorization", "Students cannot request another student’s data; faculty cannot see unassigned sections; ICT-only routes reject non-ICT roles."),
        ("Data exposure", "Automated scans confirm no password, private key, raw device hardware identifier or administrative secret appears in client bundles, QR payloads or logs."),
    ], [1.55, 5.35])
    heading(doc, "9.1 Test Evidence Expectations", 2)
    para(doc, "The delivery pipeline should run static analysis and unit tests for the Flutter client, API/protocol and database boundaries, and production build/type checks for the web portals. Security dependency audits, migration validation, authenticated integration tests and negative tests for rejected proof paths should be required before production deployment. Release builds must be signed and generated from protected branches with environment secrets held outside source control.")
    doc.add_page_break()

    heading(doc, "10 Assumptions and Future Controls")
    table(doc, ["Area", "Assumption or future control"], [
        ("Institutional data", "Student enrolment, section allocation, faculty assignments and official email data must be loaded from approved institutional sources before real deployment."),
        ("Faculty onboarding", "Faculty identity must use the deployment's approved institutional email domains. Course allocation must be imported or administered before a faculty member receives teaching scope."),
        ("Local presence", "BLE/local presence remains an extensible provider and is not the present enforcement truth. A future rollout may add it after accessibility, reliability and privacy validation."),
        ("Platform attestation", "Device make/model and a client declaration are not sufficient to prove physical hardware. Play Integrity, App Attest or managed-device policy should be evaluated before a high-assurance rollout."),
        ("Operational security", "HTTPS, secure secret management, database backups, intrusion monitoring, key rotation, security review and incident response are deployment responsibilities rather than features achieved by UI alone."),
    ], [1.65, 5.25])
    heading(doc, "10.1 Conclusion", 2)
    para(doc, "This specification defines an offline-capable, device-bound and auditable attendance platform. Its principal assurance comes from clear separation of responsibilities: mobile clients capture locally, the backend verifies authoritatively, faculty retain a controlled human fallback, and ICT governs device replacement. The resulting system is designed to remain useful during ordinary classroom connectivity loss while giving the institution evidence to investigate exceptions.")
    doc.add_page_break()

    heading(doc, "Appendix A Mermaid Diagram Source")
    para(doc, "The complete editable Mermaid source is supplied separately in architecture_mermaid.md. The four required diagrams are: Student Mobile Application, Faculty Portal, ICT Administration Portal and Connected System Context. This appendix records the source location so the diagrams can be regenerated without redrawing the architecture.")
    table(doc, ["Figure", "Source section"], [
        ("3.1", "architecture_mermaid.md  Section 1  Student Mobile Application"),
        ("3.2", "architecture_mermaid.md  Section 2  Faculty Portal"),
        ("3.3", "architecture_mermaid.md  Section 3  ICT Administration Portal"),
        ("3.4", "architecture_mermaid.md  Section 4  Connected System Context"),
    ], [1.0, 5.9])
    heading(doc, "Appendix B Glossary", 2)
    table(doc, ["Term", "Definition"], [
        ("Argon2id", "Password hashing method designed to resist offline guessing attacks."),
        ("Ed25519", "Public-key signature scheme used for compact device proof signatures."),
        ("Opaque session", "Random server-managed session token that does not expose user claims to the client."),
        ("Outbox", "Durable local queue of work awaiting successful backend processing."),
        ("Redis", "In-memory service used here for short-lived coordination, rate limits, sessions and event delivery."),
        ("PostgreSQL", "Relational database used as the authoritative institutional record."),
    ], [1.55, 5.35])

    doc.save(OUT)
    print(OUT)


if __name__ == "__main__":
    main()
