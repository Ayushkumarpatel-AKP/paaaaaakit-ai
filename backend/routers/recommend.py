"""3-tier AI recommendation engine.

Numbers and structures come from ``services.stack_solver``, which searches the
shared material database and runs every candidate through the same physics as
the digital-twin and shelf-life screens. When an LLM key is configured the model
is used **only** to explain the result in prose — it can never choose a material
or invent a number, so the recommendation screen and the simulator can never
disagree.
"""

from __future__ import annotations

from fastapi import APIRouter, HTTPException

from models.schemas import RecommendationRequest
from services.common import new_id, now_iso
from services.fallback import recommendations_for
from services.llm_client import LLMClient, LLMUnavailable, parse_json
from services.projects import on_recommendation_created
from services.prompts import RECOMMEND_SYSTEM, recommend_user_prompt
from services.stack_solver import TIERS, solve_recommendations
from services.store import get_store

router = APIRouter(prefix="/recommendations", tags=["recommendations"])

DISCLAIMER = (
    "Stack solved from the shared material database with the same physics the "
    "digital twin uses. AI-estimated — validate with a lab before production."
)

#: Fields the Flutter client parses. A tier missing any of these would break the
#: result screen, so the response is guarded before it is stored.
_REQUIRED_TIER_KEYS = (
    "structure",
    "layers",
    "otr_cc_m2_day",
    "mvtr_g_m2_day",
    "cost_per_1k",
)


def _guard_tiers(tiers: dict) -> dict:
    """Ensure every tier carries the full field set.

    The solver is the source of truth; the old templates are only used to fill a
    key the solver somehow omitted, so the response contract can never break.
    """
    fallback = recommendations_for()
    guarded: dict = {}
    for tier in TIERS:
        base = dict(fallback[tier])
        candidate = tiers.get(tier)
        if isinstance(candidate, dict):
            base.update({k: v for k, v in candidate.items() if v is not None})
        for key in _REQUIRED_TIER_KEYS:
            if not base.get(key):
                base[key] = fallback[tier][key]
        guarded[tier] = base
    return guarded


def _apply_llm_prose(tiers: dict, notes: dict) -> bool:
    """Attach the model's explanations. Returns True if anything was applied.

    Only the ``rationale`` string is read — materials, thicknesses and numbers
    stay exactly as the solver produced them.
    """
    applied = False
    for tier in TIERS:
        candidate = notes.get(tier)
        if not isinstance(candidate, dict):
            continue
        rationale = candidate.get("rationale")
        if isinstance(rationale, str) and rationale.strip():
            tiers[tier]["rationale"] = rationale.strip()
            tiers[tier]["rationale_source"] = "llm"
            applied = True
    return applied


@router.post("/generate")
def generate(payload: RecommendationRequest) -> dict:
    store = get_store()
    product = store.get("products", payload.productId)
    if not product:
        raise HTTPException(status_code=404, detail="product not found")

    # 1. Solve first. These numbers are the answer; nothing downstream may
    #    overwrite them.
    tiers = _guard_tiers(solve_recommendations(product))

    # 2. Optionally let the model explain them.
    used_llm = False
    client = LLMClient()
    if client.enabled:
        try:
            raw = client.complete(
                system=RECOMMEND_SYSTEM,
                messages=[
                    {
                        "role": "user",
                        "content": recommend_user_prompt(product, tiers),
                    }
                ],
                json_mode=True,
            )
            used_llm = _apply_llm_prose(tiers, parse_json(raw))
        except (LLMUnavailable, ValueError):
            used_llm = False

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
