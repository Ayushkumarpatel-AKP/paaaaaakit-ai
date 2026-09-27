"""AI Packaging Auditor — vision LLM proxy.

Honest framing: this is an **AI visual estimate**, not a certified inspection.
General vision models are not trained on packaging-defect datasets, so the
prompt forbids guessing and the response carries an explicit disclosure.
"""

from __future__ import annotations

from fastapi import APIRouter, File, Form, HTTPException, UploadFile

from services.common import new_id, now_iso
from services.fallback import audit_unavailable
from services.llm_client import LLMClient, LLMUnavailable, parse_json
from services.projects import on_audit_created
from services.prompts import AUDIT_PROMPT
from services.store import get_store

router = APIRouter(prefix="/audit", tags=["audit"])

DISCLOSURE = (
    "AI visual estimate — not a certified compliance inspection. Bounding "
    "boxes are approximate region centres, not pixel-accurate measurements."
)

MAX_IMAGE_BYTES = 12 * 1024 * 1024


def _normalize(parsed: dict) -> dict:
    """Coerce an LLM reply into the exact schema the Flutter parser expects."""
    layer_analysis = parsed.get("layer_analysis")
    if not isinstance(layer_analysis, dict):
        layer_analysis = {}
    normalized_layers = {
        "outer_substrate": str(layer_analysis.get("outer_substrate") or "not visible"),
        "core_barrier": str(layer_analysis.get("core_barrier") or "not visible"),
        "food_contact_liner": str(layer_analysis.get("food_contact_liner") or "not visible"),
    }

    defects = []
    for defect in parsed.get("defects") or []:
        if not isinstance(defect, dict):
            continue
        region = defect.get("region")
        entry = {
            "type": str(defect.get("type") or "unknown"),
            "severity": str(defect.get("severity") or "low"),
            "description": str(defect.get("description") or ""),
        }
        if isinstance(region, dict) and "x_pct" in region and "y_pct" in region:
            entry["region"] = {
                "x_pct": float(region["x_pct"]),
                "y_pct": float(region["y_pct"]),
            }
        defects.append(entry)

    ric = parsed.get("ric_code")
    return {
        "layer_analysis": normalized_layers,
        "defects": defects,
        "ric_code": None if ric in (None, "", "null") else str(ric),
        "compliance_note": str(
            parsed.get("compliance_note")
            or "Visual-only observation — this is not a certified compliance check."
        ),
    }


@router.post("/analyze")
async def analyze(
    image: UploadFile = File(...),
    productId: str | None = Form(default=None),
):
    image_bytes = await image.read()
    if not image_bytes:
        raise HTTPException(status_code=400, detail="empty image upload")
    if len(image_bytes) > MAX_IMAGE_BYTES:
        raise HTTPException(status_code=413, detail="image exceeds 12 MB limit")

    mime = image.content_type or "image/jpeg"
    client = LLMClient()
    used_llm = False

    if client.enabled:
        try:
            raw = client.vision(
                image_bytes=image_bytes,
                mime_type=mime,
                prompt=AUDIT_PROMPT,
                json_mode=True,
            )
            parsed = _normalize(parse_json(raw))
            used_llm = True
        except (LLMUnavailable, ValueError):
            parsed = audit_unavailable("Vision model call failed.")
    else:
        parsed = audit_unavailable("No vision model configured.")

    audit_id = new_id("audit")
    document = {
        "id": audit_id,
        "productId": productId,
        "imageUrl": None,  # set here once Firebase Storage upload is wired up
        "used_llm": used_llm,
        "disclosure": DISCLOSURE,
        "createdAt": now_iso(),
        **parsed,
    }
    store = get_store()
    store.put("audits", audit_id, document)
    on_audit_created(store, productId, document)

    return document


@router.get("")
def list_audits(productId: str | None = None, limit: int = 20) -> list[dict]:
    return get_store().list(
        "audits",
        filters={"productId": productId} if productId else None,
        order_by="createdAt",
        limit=limit,
    )
