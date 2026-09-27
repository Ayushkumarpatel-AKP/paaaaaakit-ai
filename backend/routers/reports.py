"""Project report export (server-side PDF).

Compiles product spec + recommendations + latest simulation + LCA into one PDF
using ``reportlab``. When Firebase Storage is wired up, upload the bytes and
return a signed URL instead of streaming them.
"""

from __future__ import annotations

import io

from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse

from services.store import get_store

router = APIRouter(prefix="/reports", tags=["reports"])


def _build_pdf(project_id: str) -> bytes:
    try:
        from reportlab.lib import colors
        from reportlab.lib.pagesizes import A4
        from reportlab.lib.styles import getSampleStyleSheet
        from reportlab.lib.units import mm
        from reportlab.platypus import (
            Paragraph,
            SimpleDocTemplate,
            Spacer,
            Table,
            TableStyle,
        )
    except ImportError as exc:  # pragma: no cover - optional dependency
        raise HTTPException(
            status_code=503, detail="reportlab is not installed on the server"
        ) from exc

    store = get_store()
    product = store.get("products", project_id)
    if not product:
        raise HTTPException(status_code=404, detail="product not found")

    summary = store.get("project_summary", project_id) or {}
    recommendations = store.list(
        "recommendations", filters={"productId": project_id}, order_by="createdAt", limit=1
    )
    simulations = store.list(
        "simulations", filters={"productId": project_id}, order_by="createdAt", limit=1
    )
    lca_reports = store.list(
        "lcaReports", filters={"productId": project_id}, order_by="createdAt", limit=1
    )

    styles = getSampleStyleSheet()
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(
        buffer, pagesize=A4, title=f"PackIT AI report — {product.get('name')}"
    )
    story = [
        Paragraph("PackIT AI — Packaging Engineering Report", styles["Title"]),
        Spacer(1, 6 * mm),
        Paragraph(str(product.get("name", "Untitled project")), styles["Heading2"]),
        Paragraph(
            f"Category: {product.get('category')} | Target shelf life: "
            f"{product.get('targetShelfLifeDays')} days | Format: "
            f"{product.get('packagingFormat')}",
            styles["Normal"],
        ),
        Spacer(1, 6 * mm),
        Paragraph("Product specification", styles["Heading3"]),
    ]

    spec_rows = [
        ["Water activity", product.get("waterActivity")],
        ["Fat content %", product.get("fatContent")],
        ["Oxygen sensitivity", product.get("oxygenSensitivity")],
        ["Light sensitivity", product.get("lightSensitivity")],
        ["Storage range (C)", f"{product.get('minTempC')} - {product.get('maxTempC')}"],
        ["Budget per 1k units", product.get("budgetPer1kUnits")],
    ]
    story.append(_table(spec_rows, Table, TableStyle, colors, styles["Normal"]))
    story.append(Spacer(1, 6 * mm))

    if recommendations:
        recommendation = recommendations[0]
        story.append(Paragraph("AI recommendations", styles["Heading3"]))
        for tier in ("cost_optimized", "sustainability_first", "max_barrier"):
            entry = recommendation.get(tier) or {}
            story.append(
                Paragraph(
                    f"<b>{tier.replace('_', ' ').title()}</b>: "
                    f"{entry.get('structure', 'n/a')} — OTR "
                    f"{entry.get('otr_cc_m2_day')} cc/m2/day, MVTR "
                    f"{entry.get('mvtr_g_m2_day')} g/m2/day, cost "
                    f"${entry.get('cost_per_1k')}/1k",
                    styles["Normal"],
                )
            )
        story.append(Spacer(1, 6 * mm))

    if simulations:
        simulation = simulations[0]
        story.append(Paragraph("Latest simulation", styles["Heading3"]))
        story.append(
            Paragraph(
                f"Chamber: {simulation.get('chamberPreset')} at "
                f"{simulation.get('temperatureC')} C / {simulation.get('humidityRH')}% RH | "
                f"Status: <b>{simulation.get('status')}</b> | Final quality: "
                f"{simulation.get('finalQuality')}% | Predicted shelf life: "
                f"{simulation.get('predictedShelfLifeDays')} days",
                styles["Normal"],
            )
        )
        story.append(Spacer(1, 6 * mm))

    if lca_reports:
        report = lca_reports[0]
        story.append(Paragraph("Cost & sustainability", styles["Heading3"]))
        story.append(
            Paragraph(
                f"Carbon footprint: {report.get('carbonFootprintKgCO2e')} kgCO2e | "
                f"Water: {report.get('waterUsageL')} L | Recyclability score: "
                f"{report.get('recyclabilityScore')}/100 | Landfill degradation: "
                f"{report.get('degradationYears')} years",
                styles["Normal"],
            )
        )
        story.append(Spacer(1, 6 * mm))

    story.append(
        Paragraph(
            "Generated by PackIT AI. Physics results use published literature "
            "ranges; LLM-assisted sections are engineering guidance, not lab-"
            "certified data. Validate before production.",
            styles["Italic"],
        )
    )

    doc.build(story)
    return buffer.getvalue()


def _table(rows, Table, TableStyle, colors, style):
    table = Table([[str(cell) for cell in row] for row in rows], colWidths=[60 * 1.2, 90 * 1.2])
    table.setStyle(
        TableStyle(
            [
                ("GRID", (0, 0), (-1, -1), 0.25, colors.lightgrey),
                ("FONTNAME", (0, 0), (0, -1), "Helvetica-Bold"),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ]
        )
    )
    return table


@router.post("/export/{project_id}")
def export(project_id: str) -> StreamingResponse:
    pdf_bytes = _build_pdf(project_id)
    return StreamingResponse(
        io.BytesIO(pdf_bytes),
        media_type="application/pdf",
        headers={
            "Content-Disposition": f'inline; filename="packit-report-{project_id}.pdf"'
        },
    )
