"""Generate the two-page PackIT AI technical status report.

Figures in the report were measured against the working tree on 2026-09-28
(commit d11c52a) — see ``HANDOFF.md`` for the underlying task log.

Usage (from the repo root, using the backend venv which already ships
reportlab for the server-side PDF export):

    python docs/generate_status_report.py
"""

from __future__ import annotations

from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_JUSTIFY
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import (
    KeepTogether,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)

OUTPUT = Path(__file__).resolve().parent / "PackIT_AI_Technical_Report.pdf"

ACCENT = colors.HexColor("#1D4ED8")
INK = colors.HexColor("#111827")
MUTED = colors.HexColor("#4B5563")
RULE = colors.HexColor("#D1D5DB")
BAND = colors.HexColor("#F3F4F6")

# --------------------------------------------------------------------------
# Text is restricted to Latin-1 so the built-in Helvetica fonts render it
# correctly (no rupee sign, no arrows, no subscript digits).
# --------------------------------------------------------------------------

TITLE = "PackIT AI - Technical Status Report"
SUBTITLE = (
    "Database and real-time API requirements, current progress, and the work "
    "left before this is production-ready"
)
META = (
    "Date 28 September 2026 &nbsp;|&nbsp; Branch <b>main</b> @ <b>d11c52a</b> "
    "&nbsp;|&nbsp; Flutter (Android) client + FastAPI backend"
)
PREAMBLE = (
    "Every figure below was measured or read directly out of the working tree on the date above, "
    "not estimated from design documents. Where something does not work, the evidence is named so "
    "it can be re-checked."
)

PROGRESS_INTRO = (
    "The product is a Flutter client (13 screens) on a FastAPI backend (12 routers, 16 service "
    "modules). Two parts are genuinely engineered and defensible; the rest is a convincing demo "
    "layer that degrades to bundled sample data whenever the backend is not reachable."
)

PROGRESS_ROWS = [
    [
        "3D Mockup Studio (customizer)",
        "Working - real",
        "5 bundled .glb models scoped by product family (chips vs dairy), artwork stamped as a "
        "texture, H/V/scale/rotate. model-viewer is bundled locally, so the viewer runs with no "
        "network at all.",
    ],
    [
        "Packaging stack solver",
        "Working - real",
        "1,120 candidate laminates scored with the same permeation and Arrhenius engine; 3 tiers "
        "with meets_target, limiting_factor, predicted life, thickness, INR per 1,000 and why[] "
        "reasoning.",
    ],
    [
        "Physics / LCA core",
        "Working - real",
        "Series permeability 1/TR = sum(d/P), quality-decay ODE via scipy.solve_ivp, cost and "
        "carbon from Indian market rates. Covered by 48 backend tests.",
    ],
    [
        "Wizard to API contract",
        "Working - real",
        "The user's own moisture, fat, pH, storage temperature, humidity, shelf life and budget "
        "now reach the backend. Budget used to be hardcoded (40.0) and the shelf-life key was read "
        "wrong, so real input was silently ignored.",
    ],
    [
        "Recommendation screen",
        "Working - real",
        "Invented values removed: no 95% MATCH badge, no 70-90 confidence score, no matchScore / "
        "protection literals. It now renders solver output.",
    ],
    [
        "Digital Twin Simulator",
        "Partial",
        "The animated curves are a local heuristic (a single exponential decay); a panel underneath "
        "runs the real backend engine and admits 'backend unreachable' when it cannot.",
    ],
    [
        "Packaging Auditor",
        "Partial",
        "Camera capture and the vision proxy are real, but no packaging-defect model exists - the "
        "router's own docstring says general vision models are not trained on packaging-defect "
        "datasets.",
    ],
    [
        "AI Chat Assistant",
        "Partial",
        "Real LLM only when OPENAI_API_KEY is set; otherwise a curated canned answer, so the 'AI' "
        "label overstates what the user is reading.",
    ],
    [
        "Dashboard / History / Suppliers",
        "Partial",
        "Live when the backend answers, sample data otherwise. The UI does show an explicit "
        "'live / sample data' badge rather than pretending.",
    ],
    [
        "Accounts / authentication",
        "Missing",
        "REQUIRE_AUTH defaults to false, no user model, every endpoint open.",
    ],
]

CHECK_ROWS = [
    ["flutter analyze", "No issues found (clean; two pre-existing warnings were also fixed)"],
    ["flutter test", "2 widget tests pass"],
    ["backend pytest", "48 tests pass"],
    [
        "Release APK",
        "Builds and installs; 54.6 MB (57,270,145 bytes). The committed APK predates the solver changes.",
    ],
    [
        "API latency (in-process, includes the 1,120-candidate search)",
        "/products 35 ms | /recommendations/generate 276 ms | /simulate/digital-twin 17 ms | "
        "/simulate/shelf-life 15 ms | /lca/calculate 11 ms | /chat/message 11 ms (no LLM) | "
        "/dashboard/summary 8 ms",
    ],
]

NOT_READY = [
    (
        "Backend unreachable from a real phone (critical).",
        "api_client.dart resolves Android to 10.0.2.2:8000, the emulator's alias for the host "
        "machine. On a physical device that address points at the phone itself, so the installed "
        "APK falls back to sample data everywhere except the 3D studio.",
    ),
    (
        "No persistence (critical).",
        "STORAGE_BACKEND=memory by default: all eight collections sit in an in-process dictionary "
        "and vanish on restart. The Firestore path exists but is unconfigured.",
    ),
    (
        "No authentication (critical).",
        "Every endpoint is open; anyone who can reach the host can read and write all data.",
    ),
    (
        "Release build signed with the debug keystore.",
        "build.gradle.kts still carries the 'TODO: add your own signing config' comment. Such an "
        "APK cannot be published, and each upgrade forces users to uninstall first.",
    ),
    (
        "Committed APK is stale.",
        "Built 09:24; the solver recommendations landed 09:42-10:09. The code on main is ahead of "
        "the shipped binary.",
    ),
    (
        "Tier rationale contradicts the data it ships with.",
        "When nothing meets the target, the solver falls back to the full candidate pool and "
        "correctly returns meets_target: false - yet the wording still claims the stack 'still "
        "holds the product for its target shelf life'. Measured: Potato Chips 35% fat / 180 days at "
        "65% RH reports meets_target = false on all three tiers (max barrier reaches 147.2 of 180 "
        "days).",
    ),
    (
        "Physics never validated against reality.",
        "No measured OTR/MVTR or shelf-life trials to compare against, and no light-barrier, "
        "headspace-oxygen, pasteurisation or seal-integrity term - which is why dairy reads "
        "optimistically (Pasteurized Milk at a 14-day target is offered a paperboard/LDPE pouch "
        "predicted at 30 days).",
    ),
    (
        "No real-time transport at all.",
        "No WebSocket, no SSE. Every call is blocking, with a 12 s client timeout and a 60 s LLM "
        "timeout, so an LLM chat turn is a 5-30 s blank wait.",
    ),
]

DB_INTRO = (
    "Eight logical collections are used today through a small DocumentStore interface (put / get / "
    "update / list / delete, with filters, order_by and limit). That separation is the good news: a "
    "Postgres implementation of the same interface drops in without touching a single router."
)

DB_ROWS = [
    ["Collection", "One record holds", "How it is queried", "Size"],
    ["products", "One food spec per project (~20 fields)", "get by id; list filtered by userId, ordered createdAt", "~1 KB"],
    ["simulations", "Run params + resultTimeSeries (180 points x several series)", "put per run; get by id; list filtered by productId", "20-60 KB"],
    ["recommendations", "3 tiers, metrics, why[] reasoning", "put on generate; list filtered by productId", "~5 KB"],
    ["audits", "Vision verdict + layer analysis + image ref", "put; list filtered by productId", "2-10 KB + image"],
    ["chat_messages", "One row per turn: sessionId, role, content", "put per turn; list filtered by sessionId", "~1 KB"],
    ["suppliers", "Catalogue entry: grade, region, price/kg, rating", "list ordered by rating; get by id", "~1 KB"],
    ["rfq_requests", "Outbound quote request to a supplier", "put; list", "~1 KB"],
    ["project_summary", "Roll-up per project", "get / list", "~2 KB"],
]

DB_QUERY_NOTE = (
    "<b>What the query load actually looks like:</b> equality filters on userId / productId / "
    "sessionId, ordering by createdAt and by rating, limit-offset paging, and a write chain "
    "(product -> simulation -> recommendation) that should be transactional. The spec fields also "
    "evolve, which argues against a rigid column-per-field table."
)

DB_RECO = (
    "<b>Recommended engine: PostgreSQL 16, managed (Neon, Supabase or RDS).</b> Relational tables "
    "for what is filtered and joined (products, suppliers, rfq_requests, chat_messages); JSONB for "
    "shapes that are still moving (the physics time series and per-tier payloads); foreign keys "
    "with ON DELETE CASCADE from simulations, recommendations and audits to products. Indexes: "
    "(userId, createdAt DESC) on products; (productId, createdAt DESC) on simulations / "
    "recommendations / audits; (sessionId, createdAt) on chat_messages; (rating DESC) on "
    "suppliers. Connection pooling is required, not optional - the API is async FastAPI."
)

DDL = """products(id pk, user_id, name, category, spec jsonb, created_at)
simulations(id pk, product_id fk, kind, params jsonb, series jsonb, created_at)
recommendations(id pk, product_id fk, tiers jsonb, used_llm bool, created_at)
audits(id pk, product_id fk, verdict jsonb, image_uri text, created_at)
chat_messages(id pk, session_id, role, content, created_at)
suppliers(id pk, name, region, rating, meta jsonb)
rfq_requests(id pk, supplier_id fk, payload jsonb, status, created_at)"""

DB_ALSO = [
    (
        "<b>Cache (Redis).</b>",
        "The 1,120-candidate search costs 276 ms and is a pure function of (spec, storage "
        "conditions). Memoising it by spec hash turns repeat views into roughly 0 ms. Redis also "
        "holds rate-limit counters and job state.",
    ),
    (
        "<b>Object storage (S3-compatible).</b>",
        "Audit images and exported report PDFs belong in a bucket with a URL stored in the row, "
        "never base64 inside Postgres. reportlab already renders the PDF export server-side.",
    ),
    (
        "<b>Migrations, backups and retention.</b>",
        "Alembic for schema versioning (there is none today); daily snapshots with point-in-time "
        "recovery, 7-30 day retention; and a written retention/deletion policy, because chat "
        "transcripts and audits hold PII and product specs can be commercially sensitive.",
    ),
    (
        "<b>Sizing, and why not Firestore.</b>",
        "One project (product + 3 simulations + a recommendation + 1-2 audits) is roughly "
        "100-200 KB excluding images, so 10,000 projects a year is 1-2 GB - a single small managed "
        "instance covers years. A FirestoreStore already exists and handles the simple get/put "
        "paths, but the filtered-and-ordered list calls are exactly where NoSQL charges a composite "
        "index per filter combination; keep it only if you specifically want mobile offline sync.",
    ),
]

RT_INTRO = (
    "The API today is pure request/response REST: no WebSocket, no SSE, no streaming endpoint. The "
    "client timeout is 12 s, the LLM timeout is configured at 60 s, and image upload is one "
    "blocking multipart POST."
)

RT_ROWS = [
    ["Interaction", "Today", "What it actually needs"],
    ["Chat reply", "5-30 s blank wait for one JSON blob (or instant canned text)", "SSE stream of tokens (text/event-stream), first token under 1 s. Highest-value real-time win."],
    ["Audit image analysis", "One blocking POST, no progress, no cancel", "202 Accepted + jobId, then SSE or poll for the verdict; upload progress on the client."],
    ["Simulation runs", "15-20 ms, synchronous", "Nothing. Keep it synchronous."],
    ["Recommendation search", "276 ms, synchronous", "Nothing. Cache the result in Redis."],
    ["What-if sweeps (multi-variant)", "Not implemented", "Background job queue with progress events."],
    ["Dashboard / History", "Re-fetched when the screen opens", "Fine as-is; optional ETag / conditional GET."],
    ["Job notifications", "None", "FCM push when a background job finishes."],
]

RT_RECO = (
    "<b>Choose SSE over WebSocket.</b> The traffic is one-directional (server to client progress "
    "and tokens), SSE runs over plain HTTP/1.1, reconnects automatically, and survives proxies and "
    "flaky mobile networks far better than a socket. WebSocket only becomes worth it if "
    "collaborative multi-user editing is ever built, which nothing in this app needs today."
)

RT_ALSO = (
    "<b>Also required before this counts as a real API:</b> URL versioning (/v1); JWT auth with "
    "refresh tokens; per-user rate limits; idempotency keys on POST /products and /simulate so a "
    "retry cannot duplicate a project; request-size limits on uploads; gzip; structured logs with "
    "request tracing; and health/readiness probes (a /health endpoint already exists and reports "
    "storage status)."
)

ROADMAP = [
    ["Priority", "Work item", "Effort"],
    ["P0 - ship blocker", "Deploy the FastAPI service (Docker + Fly/Render/Cloud Run) and rebuild the APK with --dart-define=API_BASE_URL=https://... . Without this the app is a demo, not a product.", "1 day"],
    ["P0 - ship blocker", "Implement the Postgres DocumentStore and switch STORAGE_BACKEND off memory, so data survives restarts.", "1-2 days"],
    ["P0 - ship blocker", "Generate a real release keystore and replace the debug signing config.", "Half a day"],
    ["P0 - ship blocker", "Fix the tier rationale text so it can never claim a target the stack missed.", "Hours"],
    ["P1 - usable by real users", "Authentication (JWT), per-user rate limiting and data isolation.", "1-2 days"],
    ["P1 - usable by real users", "SSE streaming for the chat assistant, and object storage for audit images and report exports.", "2 days"],
    ["P1 - usable by real users", "Rebuild and commit the APK so the shipped binary matches main.", "Half a day"],
    ["P2 - trustworthy results", "Validate the physics against measured OTR/MVTR and real shelf-life trials; calibrate or add the missing light, headspace-oxygen and seal-integrity terms.", "Weeks"],
    ["P2 - trustworthy results", "Background job queue with FCM notifications, plus monitoring, error tracking and an audit trail for spec changes.", "4-6 days"],
    ["P2 - trustworthy results", "Offline-first local cache on the device so the wizard keeps working with no signal.", "1 week"],
]

BOTTOM_LINE = (
    "<b>Bottom line:</b> the 3D mockup studio and the physics/solver backend are genuinely real and "
    "worth keeping. What stands between this and a product is not more features - it is deployment, "
    "a persistent database, authentication and release signing, followed by honest validation of "
    "the physics against measured data."
)


def styles() -> dict[str, ParagraphStyle]:
    base = getSampleStyleSheet()
    return {
        "title": ParagraphStyle(
            "title", parent=base["Title"], fontName="Helvetica-Bold", fontSize=15,
            leading=17, textColor=ACCENT, alignment=0, spaceAfter=1,
        ),
        "subtitle": ParagraphStyle(
            "subtitle", parent=base["Normal"], fontName="Helvetica", fontSize=8.7,
            leading=10.4, textColor=MUTED, spaceAfter=3,
        ),
        "meta": ParagraphStyle(
            "meta", parent=base["Normal"], fontName="Helvetica", fontSize=7.8,
            leading=9.6, textColor=INK, spaceAfter=2,
        ),
        "h1": ParagraphStyle(
            "h1", parent=base["Normal"], fontName="Helvetica-Bold", fontSize=10,
            leading=11.5, textColor=ACCENT, spaceBefore=6.5, spaceAfter=3,
        ),
        "h2": ParagraphStyle(
            "h2", parent=base["Normal"], fontName="Helvetica-Bold", fontSize=8.4,
            leading=9.8, textColor=INK, spaceBefore=4, spaceAfter=2,
        ),
        "body": ParagraphStyle(
            "body", parent=base["Normal"], fontName="Helvetica", fontSize=7.9,
            leading=9.6, textColor=INK, alignment=TA_JUSTIFY, spaceAfter=3,
        ),
        "cell": ParagraphStyle(
            "cell", parent=base["Normal"], fontName="Helvetica", fontSize=6.9,
            leading=8.3, textColor=INK,
        ),
        "cellb": ParagraphStyle(
            "cellb", parent=base["Normal"], fontName="Helvetica-Bold", fontSize=6.9,
            leading=8.3, textColor=INK,
        ),
        "head": ParagraphStyle(
            "head", parent=base["Normal"], fontName="Helvetica-Bold", fontSize=7.1,
            leading=8.5, textColor=colors.white,
        ),
        "mono": ParagraphStyle(
            "mono", parent=base["Normal"], fontName="Courier", fontSize=6.5,
            leading=8.1, textColor=INK,
        ),
        "bullet": ParagraphStyle(
            "bullet", parent=base["Normal"], fontName="Helvetica", fontSize=7.7,
            leading=9.2, textColor=INK, alignment=TA_JUSTIFY,
            leftIndent=9, bulletIndent=1, spaceAfter=1.8,
        ),
    }


def table(rows, widths, st, *, header=True, zebra=True) -> Table:
    converted = []
    for r_index, row in enumerate(rows):
        cells = []
        for cell in row:
            style = st["head"] if (header and r_index == 0) else (
                st["cellb"] if (not header and r_index == 0) else st["cell"]
            )
            cells.append(Paragraph(str(cell), style))
        converted.append(cells)

    tbl = Table(converted, colWidths=widths, repeatRows=1 if header else 0)
    commands = [
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING", (0, 0), (-1, -1), 1.9),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 1.9),
        ("LEFTPADDING", (0, 0), (-1, -1), 3.5),
        ("RIGHTPADDING", (0, 0), (-1, -1), 3.5),
        ("LINEBELOW", (0, 0), (-1, -2), 0.25, RULE),
        ("BOX", (0, 0), (-1, -1), 0.5, RULE),
    ]
    if header:
        commands.append(("BACKGROUND", (0, 0), (-1, 0), ACCENT))
    if zebra:
        start = 1 if header else 0
        for i in range(start, len(rows)):
            if (i - start) % 2 == 1:
                commands.append(("BACKGROUND", (0, i), (-1, i), BAND))
    tbl.setStyle(TableStyle(commands))
    return tbl


def bullets(items, st) -> list:
    return [
        Paragraph(f"{lead} {rest}", st["bullet"], bulletText="\u2022")
        for lead, rest in items
    ]


def build() -> None:
    st = styles()
    doc = SimpleDocTemplate(
        str(OUTPUT),
        pagesize=A4,
        leftMargin=11 * mm,
        rightMargin=11 * mm,
        topMargin=9 * mm,
        bottomMargin=9 * mm,
        title="PackIT AI - Technical Status Report",
        author="PackIT AI engineering notes",
        subject="Database and real-time API requirements, current progress, and path to production",
    )

    W = doc.width
    story: list = []

    def footer(canvas, _doc):
        canvas.saveState()
        canvas.setFont("Helvetica", 6.6)
        canvas.setFillColor(MUTED)
        canvas.drawString(
            doc.leftMargin, 5.5 * mm,
            "PackIT AI - Technical Status Report - 28 Sep 2026 - main @ d11c52a",
        )
        canvas.drawRightString(doc.leftMargin + W, 5.5 * mm, f"Page {canvas.getPageNumber()} of 2")
        canvas.setStrokeColor(RULE)
        canvas.setLineWidth(0.4)
        canvas.line(doc.leftMargin, 8 * mm, doc.leftMargin + W, 8 * mm)
        canvas.restoreState()

    # ---- header ---------------------------------------------------------
    story.append(Paragraph(TITLE, st["title"]))
    story.append(Paragraph(SUBTITLE, st["subtitle"]))
    story.append(Paragraph(META, st["meta"]))
    story.append(Paragraph(PREAMBLE, st["body"]))

    # ---- 1. progress ----------------------------------------------------
    story.append(Paragraph("1. Where the project stands today", st["h1"]))
    story.append(Paragraph(PROGRESS_INTRO, st["body"]))
    story.append(
        table(
            [["Component", "Status", "Evidence"]]
            + [[a, f"<b>{b}</b>", c] for a, b, c in PROGRESS_ROWS],
            [W * 0.235, W * 0.10, W * 0.665],
            st,
        )
    )

    story.append(Paragraph("Verified checks", st["h2"]))
    story.append(table([["Check", "Result"]] + CHECK_ROWS, [W * 0.28, W * 0.72], st))

    # ---- 2. gaps --------------------------------------------------------
    story.append(Paragraph("2. What is not ready, and the evidence for it", st["h1"]))
    story.extend(bullets(NOT_READY, st))

    # ---- page 2 ---------------------------------------------------------
    story.append(Paragraph("3. What kind of database this project needs", st["h1"]))
    story.append(Paragraph(DB_INTRO, st["body"]))
    story.append(table(DB_ROWS, [W * 0.15, W * 0.335, W * 0.375, W * 0.14], st))
    story.append(Spacer(1, 2.5))
    story.append(Paragraph(DB_QUERY_NOTE, st["body"]))
    story.append(Paragraph(DB_RECO, st["body"]))
    story.append(Paragraph("Implied schema", st["h2"]))
    story.append(
        Table(
            [[Paragraph(DDL.replace("\n", "<br/>"), st["mono"])]],
            colWidths=[W],
            style=TableStyle([
                ("BACKGROUND", (0, 0), (-1, -1), BAND),
                ("BOX", (0, 0), (-1, -1), 0.4, RULE),
                ("LEFTPADDING", (0, 0), (-1, -1), 5),
                ("RIGHTPADDING", (0, 0), (-1, -1), 5),
                ("TOPPADDING", (0, 0), (-1, -1), 3),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
            ]),
        )
    )
    story.append(Spacer(1, 2.5))
    story.extend(bullets(DB_ALSO, st))

    # ---- 4. real-time ---------------------------------------------------
    story.append(Paragraph("4. What kind of real-time API this app needs", st["h1"]))
    story.append(Paragraph(RT_INTRO, st["body"]))
    story.append(table(RT_ROWS, [W * 0.19, W * 0.35, W * 0.46], st))
    story.append(Spacer(1, 2.5))
    story.append(Paragraph(RT_RECO, st["body"]))
    story.append(Paragraph(RT_ALSO, st["body"]))

    # ---- 5. roadmap -----------------------------------------------------
    story.append(Paragraph("5. Roadmap from demo to production", st["h1"]))
    story.append(table(ROADMAP, [W * 0.17, W * 0.745, W * 0.085], st))
    story.append(Spacer(1, 3))
    story.append(
        KeepTogether(
            Table(
                [[Paragraph(BOTTOM_LINE, st["body"])]],
                colWidths=[W],
                style=TableStyle([
                    ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#EFF6FF")),
                    ("BOX", (0, 0), (-1, -1), 0.6, ACCENT),
                    ("LEFTPADDING", (0, 0), (-1, -1), 6),
                    ("RIGHTPADDING", (0, 0), (-1, -1), 6),
                    ("TOPPADDING", (0, 0), (-1, -1), 4),
                    ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
                ]),
            )
        )
    )

    doc.build(story, onFirstPage=footer, onLaterPages=footer)
    print(f"wrote {OUTPUT}")


if __name__ == "__main__":
    build()
