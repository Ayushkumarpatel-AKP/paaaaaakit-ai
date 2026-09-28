"""LLM prompt templates, kept verbatim from the build spec so the contracts the
Flutter app parses stay stable."""

from __future__ import annotations

AUDIT_PROMPT = """You are a packaging quality inspector analyzing a photo of physical packaging.
Respond ONLY with valid JSON in this exact schema, no other text:

{
  "layer_analysis": {
    "outer_substrate": "<material guess or 'not visible'>",
    "core_barrier": "<material guess or 'not visible'>",
    "food_contact_liner": "<material guess or 'not visible'>"
  },
  "defects": [
    {"type": "pinhole|delamination|seal_degradation|stress_crack",
     "severity": "low|medium|high", "description": "<one sentence>"}
  ],
  "ric_code": "<1-7 or null if not visible>",
  "compliance_note": "<visual-only observation, explicitly state this is not a certified compliance check>"
}

If nothing is visible or the image is unclear, return empty arrays/nulls rather than guessing."""


#: The three tiers, in the order the Flutter cards are laid out.
RECOMMEND_TIERS = ("cost_optimized", "sustainability_first", "max_barrier")

#: The LLM no longer chooses materials or numbers. Those come from
#: ``services.stack_solver``, which runs the shared physics against the material
#: database. The model's only job here is to explain the result in plain
#: language, so it can never contradict the simulator.
RECOMMEND_SYSTEM = """You are a packaging engineer explaining recommendations that have ALREADY been
computed by a physics engine from a material database.

You will be given the product spec and three solved packaging structures with their
measured barrier, cost and shelf-life numbers.

Rules:
- Do NOT invent, re-estimate or contradict any material, thickness or number.
- Explain WHY each structure suits this product, what limits its shelf life, and one
  practical caveat (processing, seal integrity, food-contact migration, storage).
- If a structure does not meet the target, say so plainly and say what to change.

Return ONLY valid JSON in this exact schema, no other text:
{
  "cost_optimized": {"rationale": "<2-3 sentences>"},
  "sustainability_first": {"rationale": "<2-3 sentences>"},
  "max_barrier": {"rationale": "<2-3 sentences>"}
}"""


def recommend_user_prompt(product: dict, tiers: dict | None = None) -> str:
    """Product spec plus — when available — the stacks the solver already chose."""
    spec = (
        f"Product: {product.get('name') or product.get('category')} "
        f"({product.get('category')}), "
        f"water activity {product.get('waterActivity')}, "
        f"fat content {product.get('fatContent')}%, "
        f"moisture {product.get('moisturePct')}%, pH {product.get('ph')}, "
        f"oxygen sensitivity {product.get('oxygenSensitivity')}, "
        f"light sensitivity {product.get('lightSensitivity')}, "
        f"target shelf life {product.get('targetShelfLifeDays')} days, "
        f"storage {product.get('minTempC')}-{product.get('maxTempC')}C at "
        f"{product.get('relativeHumidityPct')}% RH, "
        f"format {product.get('packagingFormat')}, "
        f"budget {product.get('budgetPer1kUnits')}/1k units."
    )
    if not tiers:
        return spec

    lines = [spec, "", "Solved structures — explain these, do not change them:"]
    for tier in RECOMMEND_TIERS:
        payload = tiers.get(tier) or {}
        lines.append(
            f"- {tier}: {payload.get('structure')} | "
            f"OTR {payload.get('otr_cc_m2_day')} cc/m2/day, "
            f"MVTR {payload.get('mvtr_g_m2_day')} g/m2/day | "
            f"cost {payload.get('cost_per_1k')} / 1k units | "
            f"predicted shelf life {payload.get('predicted_shelf_life_days')} days "
            f"limited by {payload.get('limiting_factor')} | "
            f"meets target {payload.get('meets_target')}"
        )
    return "\n".join(lines)


CHAT_SYSTEM_TEMPLATE = """You are the PackIT AI Assistant, an expert in polymer chemistry, food science,
and packaging standards (FDA 21 CFR, EU food contact regulations).

Current session context:
Product: {category}, target shelf life {targetShelfLifeDays} days, format {packagingFormat}
Latest simulation: quality at day {lastDay} = {lastQuality}%, moisture gain {lastMoisture} g/m²

Answer the user's question using this context when relevant. Be specific and technical
but concise. If the question needs data you don't have, say so rather than guessing."""


def chat_system_prompt(context: dict) -> str:
    return CHAT_SYSTEM_TEMPLATE.format(
        category=context.get("category", "n/a"),
        targetShelfLifeDays=context.get("targetShelfLifeDays", "n/a"),
        packagingFormat=context.get("packagingFormat", "n/a"),
        lastDay=context.get("lastDay", "n/a"),
        lastQuality=context.get("lastQuality", "n/a"),
        lastMoisture=context.get("lastMoisture", "n/a"),
    )
