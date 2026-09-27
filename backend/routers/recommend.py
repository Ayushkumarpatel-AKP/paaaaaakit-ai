"""3-tier AI recommendation engine (text LLM + grounded fallback)."""

from __future__ import annotations

from fastapi import APIRouter, HTTPException

from models.schemas import RecommendationRequest
from services.common import new_id, now_iso
from services.fallback import recommendations_for
from services.llm_client import LLMClient, LLMUnavailable, parse_json
from services.projects import on_recommendation_created
from services.prompts import RECOMMEND_SYSTEM, recommend_user_prompt
from services.store import get_store

router = APIRouter(prefix="/recommendations", tags=["recommendations"])

TIERS = ("cost_optimized", "sustainability_first", "max_barrier")

DISCLAIMER = (
    "AI-estimated based on published material ranges — validate with a lab "
    "before production."
)


def _merge_with_fallback(parsed: dict) -> dict:
    """Guarantee every tier has the full field set.

    LLM output is treated as a *suggestion* for structure/numbers; missing
    fields (or a missing tier) fall back to the material-database values so the
    response contract never breaks the Flutter parser.
    """
    fallback = recommendations_for()
    merged: dict = {}
    for tier in TIERS:
        base = dict(fallback[tier])
        candidate = parsed.get(tier) if isinstance(parsed.get(tier), dict) else {}
        for key in (
            "structure",
            "mvtr_g_m2_day",
            "otr_cc_m2_day",
            "cost_per_1k",
            "carbon_kgco2e_per_kg",
        ):
            value = candidate.get(key)
            if isinstance(value, (int, float)) or (isinstance(value, str) and value.strip()):
                base[key] = value
        # Layers come from the DB (so LCA/layer-stack screens stay consistent);
        # the LLM only names the structure.
        merged[tier] = base
    return merged


@router.post("/generate")
def generate(payload: RecommendationRequest) -> dict:
    store = get_store()
    product = store.get("products", payload.productId)
    if not product:
        raise HTTPException(status_code=404, detail="product not found")

    used_llm = False
    tiers: dict
    client = LLMClient()
    if client.enabled:
        try:
            raw = client.complete(
                system=RECOMMEND_SYSTEM,
                messages=[{"role": "user", "content": recommend_user_prompt(product)}],
                json_mode=True,
            )
            tiers = _merge_with_fallback(parse_json(raw))
            used_llm = True
        except (LLMUnavailable, ValueError):
            tiers = recommendations_for()
    else:
        tiers = recommendations_for()

    rec_id = new_id("rec")
    document = {
        "id": rec_id,
        "productId": product["id"],
        "userId": product.get("userId", "demo-user"),
        "used_llm": used_llm,
        "createdAt": now_iso(),
        **tiers,
    }
    store.put("recommendations", rec_id, document)
    on_recommendation_created(store, product, document)

    return {**document, "disclaimer": DISCLAIMER}


@router.get("/{product_id}")
def latest(product_id: str) -> dict:
    recommendations = get_store().list(
        "recommendations",
        filters={"productId": product_id},
        order_by="createdAt",
        limit=1,
    )
    if not recommendations:
        raise HTTPException(status_code=404, detail="no recommendations for product")
    return recommendations[0]
