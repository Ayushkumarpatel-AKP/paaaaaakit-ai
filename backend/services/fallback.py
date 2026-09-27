"""Deterministic fallbacks used when no LLM key is configured.

The numbers here are *not* invented: every stack is scored with the same
``material_db`` + ``permeability`` + ``lca`` code paths the physics screens use,
so a no-key demo still shows internally consistent results.
"""

from __future__ import annotations

from services import lca as lca_service
from services.material_db import find_material
from services.permeability import series_transmission

#: Assumed package surface area for per-1k-unit cost estimates.
PACKAGE_AREA_M2 = 0.05

RECOMMENDATION_TEMPLATES: dict[str, list[dict]] = {
    "cost_optimized": [
        {"material": "pet", "thicknessUm": 12},
        {"material": "met_pet", "thicknessUm": 12},
        {"material": "ldpe", "thicknessUm": 60},
    ],
    "sustainability_first": [
        {"material": "pla", "thicknessUm": 25},
        {"material": "nanocellulose", "thicknessUm": 10},
        {"material": "pla", "thicknessUm": 40},
    ],
    "max_barrier": [
        {"material": "pet", "thicknessUm": 12},
        {"material": "alox_pet", "thicknessUm": 12},
        {"material": "evoh", "thicknessUm": 15},
        {"material": "ldpe", "thicknessUm": 60},
    ],
}

TIER_DESCRIPTIONS = {
    "cost_optimized": "PET / metallized PET / LDPE — standard polyolefin laminate.",
    "sustainability_first": "PLA / nanocellulose / compostable sealant — designed for compostability.",
    "max_barrier": "PET / AlOx-coated PET / EVOH / LDPE co-extrusion — highest barrier.",
}


def stack_metrics(layers: list[dict]) -> dict:
    """Barrier + cost + carbon metrics for a stack, using the shared engines."""
    permeability = series_transmission(layers)
    cost = lca_service.cost_breakdown(
        layers, area_m2=PACKAGE_AREA_M2, units=1000
    )
    carbon = lca_service.carbon_footprint(
        layers, area_m2=PACKAGE_AREA_M2, units=1000
    )
    total_mass = sum(
        layer["thicknessUm"] * 1e-3 * find_material(layer["material"]).density
        for layer in layers
    )
    carbon_per_kg = (
        carbon["material_kgco2e_per_unit"] / total_mass if total_mass > 0 else 0.0
    )
    return {
        "structure": " / ".join(
            f"{find_material(l['material']).name.split(' (')[0]} {l['thicknessUm']}um"
            for l in layers
        ),
        "mvtr_g_m2_day": round(permeability.mvtr, 3),
        "otr_cc_m2_day": round(permeability.otr, 3),
        #: INR (\u20b9) — Indian market pricing
        "cost_per_1k": round(cost["per_1k_units"]["total"], 2),
        "cost_per_unit": round(cost["per_unit"]["total"], 3),
        "currency": cost["currency"],
        "carbon_kgco2e_per_kg": round(carbon_per_kg, 3),
        "layers": layers,
        "totalThicknessUm": round(permeability.total_thickness_um, 1),
    }


def recommendations_for(_product: dict | None = None) -> dict:
    """Three-tier recommendation set generated from the material database."""
    out: dict = {}
    for tier, layers in RECOMMENDATION_TEMPLATES.items():
        metrics = stack_metrics(layers)
        metrics["tier"] = tier
        metrics["rationale"] = TIER_DESCRIPTIONS[tier]
        out[tier] = metrics
    return out


def audit_unavailable(reason: str = "No vision model configured.") -> dict:
    """Schema-valid auditor response used when vision is unavailable."""
    return {
        "layer_analysis": {
            "outer_substrate": "not visible",
            "core_barrier": "not visible",
            "food_contact_liner": "not visible",
        },
        "defects": [],
        "ric_code": None,
        "compliance_note": (
            "AI visual estimate only — this is not a certified compliance check. "
            f"({reason})"
        ),
        "model_used": False,
    }


def chat_answer(context: dict, question: str) -> str:
    """Context-aware canned answer (no LLM key)."""
    q = (question or "").lower()
    category = context.get("category") or "your product"
    quality = context.get("lastQuality")
    target = context.get("targetShelfLifeDays")
    fmt = context.get("packagingFormat")

    context_line = (
        f"For {category} with a {target}-day target shelf life in {fmt} packaging, "
        if target and fmt
        else f"For {category}, "
    )

    if any(w in q for w in ("arrhenius", "activation", "ea", "temperature")):
        return (
            context_line
            + "quality loss follows a first-order Arrhenius model: k = A·exp(-Ea/RT). "
            "Raising storage temperature by 10 °C roughly doubles-to-triples k, so "
            "a tropical chamber (~38 °C) shortens predicted shelf life sharply. "
            "The Digital Twin screen integrates this ODE directly."
        )
    if any(w in q for w in ("evoh", "barrier", "otr", "oxygen")):
        return (
            context_line
            + "oxygen ingress is computed with series permeability: 1/OTR_total = "
            "Σ(d_i/P_i). EVOH is an excellent dry oxygen barrier (~6 cc·µm/m²·day) "
            "but its moisture sensitivity means it should be buried between "
            "moisture-barrier tie layers (e.g. PE) in humid conditions."
        )
    if any(w in q for w in ("moisture", "mvtr", "humidity", "water")):
        return (
            context_line
            + "moisture gain is approximated with a Fickian model driven by the "
            "MVTR of the stack and the RH gradient. For crispy snacks a cumulative "
            "gain above roughly 3 g/m² is where texture loss becomes noticeable — "
            "that is the critical threshold the Shelf Life screen checks."
        )
    if any(w in q for w in ("recycl", "sustainab", "compost", "epr")):
        return (
            context_line
            + "recyclability favours mono-material and compostable stacks; each "
            "additional material layer penalises the score because separation is "
            "harder. The LCA screen also compares your current plastic mass to a "
            "suggested eco-stack under an illustrative EPR rate."
        )
    if quality is not None:
        return (
            context_line
            + f"the latest simulation ends at {quality}% quality. Ask me about "
            "barrier materials, moisture gain, oxidation or recyclability and I'll "
            "explain how the model behaves. (Running in offline mode — set "
            "OPENAI_API_KEY on the backend for open-ended answers.)"
        )
    return (
        context_line
        + "I can explain barrier selection, moisture gain, oxidation kinetics and "
        "recyclability trade-offs. (Running in offline mode — set OPENAI_API_KEY "
        "on the backend for open-ended answers.)"
    )
