"""Solve packaging stacks against a product's own barrier targets.

The three-tier recommendation used to be three hardcoded layer stacks — the same
PET / metallised-PET / LDPE answer for chips, milk and beef. This module instead:

1. enumerates a bounded set of realistic flexible-laminate candidates built from
   ``material_db``;
2. evaluates each candidate with the **same** physics the digital-twin and
   shelf-life screens use (Fickian moisture uptake, headspace oxygen balance,
   peroxide value, microbial growth);
3. keeps only the stacks that actually hold the product for its target shelf
   life, then picks three tiers out of that feasible set.

Nothing here is an LLM — every number comes from the shared material database and
the shared physics modules.
"""

from __future__ import annotations

from dataclasses import dataclass

from services import arrhenius, shelf_life
from services.digital_twin import AMBIENT_O2_FRACTION, oxygen_accumulation
from services.fallback import stack_metrics
from services.lca import recyclability_score
from services.material_db import find_material
from services.permeability import series_transmission
from services.shelf_life import category_spec

#: Role -> material key -> thickness options (microns).
#:
#: A flexible laminate is a print/outer web, an optional barrier core and a
#: heat-seal layer. Keep these grids small: the search is the product of the
#: three (see ``_candidates``), so widen by adding materials, not by adding
#: thickness steps.
OUTER_OPTIONS: dict[str, tuple[float, ...]] = {
    "pet": (12.0, 15.0, 20.0),
    "bopp": (15.0, 20.0),
    "paperboard": (40.0,),
    "pla": (20.0, 25.0),
    "nanocellulose": (10.0,),
}

BARRIER_OPTIONS: dict[str, tuple[float, ...]] = {
    "met_pet": (12.0, 15.0),
    "alox_pet": (12.0,),
    "evoh": (9.0, 12.0, 15.0),
    "alu_foil": (7.0, 9.0),
    "nanocellulose": (10.0, 15.0),
}

SEALANT_OPTIONS: dict[str, tuple[float, ...]] = {
    "ldpe": (40.0, 50.0, 60.0, 80.0),
    "pp": (40.0, 60.0),
    "ionomer": (50.0,),
    "pla": (40.0, 60.0),
    "bio_coating": (30.0,),
    "hdpe": (40.0, 60.0),
}

TIERS = ("cost_optimized", "sustainability_first", "max_barrier")

#: Integrate a little past the target so a stack that only *just* passes is not
#: rejected for crossing the line on the last simulated day.
_WINDOW_FACTOR = 1.25
_MIN_WINDOW_DAYS = 30.0
_N_POINTS = 41

#: Predicted shelf life within this many days of the target still counts as met,
#: so floating-point noise and grid interpolation do not flip a tier.
_TOLERANCE_DAYS = 1.0

_TIER_RATIONALE = {
    "cost_optimized": (
        "Cheapest stack in the material database that still holds the product "
        "for its target shelf life."
    ),
    "sustainability_first": (
        "Highest recyclability score (shared LCA engine) among the stacks that "
        "meet the target. Compostable layers and mono-material designs score "
        "higher there, and fewer layers means easier separation."
    ),
    "max_barrier": (
        "Lowest combined oxygen and moisture transmission — the largest safety "
        "margin if storage is hotter or longer than planned."
    ),
}


@dataclass(frozen=True)
class Candidate:
    """One layer stack: an ordered tuple of ``(material key, microns)``."""

    layers: tuple[tuple[str, float], ...]

    def as_dicts(self) -> list[dict]:
        return [
            {"material": material, "thicknessUm": thickness}
            for material, thickness in self.layers
        ]

    @property
    def signature(self) -> str:
        return "|".join(f"{m}:{t:g}" for m, t in self.layers)


def _candidates() -> list[Candidate]:
    """Every realistic laminate in the search space.

    2-layer (outer + sealant) and 3-layer (outer + barrier + sealant) forms.
    A material is never used twice in the same stack.
    """
    out: list[Candidate] = []
    for outer, outer_grid in OUTER_OPTIONS.items():
        for outer_um in outer_grid:
            for sealant, sealant_grid in SEALANT_OPTIONS.items():
                if sealant == outer:
                    continue
                for sealant_um in sealant_grid:
                    out.append(Candidate(((outer, outer_um), (sealant, sealant_um))))
                    for barrier, barrier_grid in BARRIER_OPTIONS.items():
                        if barrier in (outer, sealant):
                            continue
                        for barrier_um in barrier_grid:
                            out.append(
                                Candidate(
                                    (
                                        (outer, outer_um),
                                        (barrier, barrier_um),
                                        (sealant, sealant_um),
                                    )
                                )
                            )
    return out


def _role(index: int, count: int) -> str:
    if index == 0:
        return "outer / print web"
    if index == count - 1:
        return "heat-seal layer"
    return "barrier core"


def _why(layers: list[dict], result, target_days: float) -> list[str]:
    """Plain-language reasons a buyer can act on, one per layer."""
    out: list[str] = []
    count = len(layers)
    for index, layer in enumerate(layers):
        material = find_material(layer["material"])
        out.append(
            f"{material.name} {layer['thicknessUm']:g} µm — {_role(index, count)}"
        )

    if result.limiting_factor == "moisture":
        out.append(
            "Moisture uptake is the limiting factor: this stack reaches the "
            f"{target_days:g}-day target, but a thicker sealant or a better "
            "moisture barrier would add margin."
        )
    elif result.limiting_factor == "oxidation":
        out.append(
            "Oxidation is the limiting factor: the fat content needs the oxygen "
            "barrier core to stay under the peroxide limit."
        )
    elif result.limiting_factor == "microbial":
        out.append(
            "Microbial growth is the limiting factor and does not improve with a "
            "better film — this product needs temperature control or MAP."
        )
    elif result.limiting_factor == "quality":
        out.append(
            "Quality decay is the limiting factor; it is set by the product "
            "itself, so the film is not the constraint here."
        )
    return out


@dataclass
class _Evaluation:
    layers: list[dict]
    payload: dict


def _evaluate(
    candidate: Candidate,
    *,
    product: dict,
    time_days: list[float],
    quality: list[float],
    duration: float,
    temperature_c: float,
    humidity: float,
    fat: float,
    aw: float,
    target_days: float,
    budget: float,
) -> _Evaluation:
    """Run one candidate through the shared physics and cost engines."""
    layers = candidate.as_dicts()
    permeability = series_transmission(layers)
    spec = category_spec(product.get("category"))

    moisture = shelf_life.moisture_gain_curve(
        permeability.mvtr,
        humidity,
        spec.equilibrium_rh_pct,
        duration,
        n_points=len(time_days),
        temperature_c=temperature_c,
    )
    oxygen = oxygen_accumulation(
        otr=permeability.otr,
        o2_start_fraction=AMBIENT_O2_FRACTION,
        duration_days=duration,
        n_points=len(time_days),
        temperature_c=temperature_c,
        fat_content_pct=fat,
    )
    result = shelf_life.predict_shelf_life(
        category=product.get("category"),
        time_days=time_days,
        quality=quality,
        moisture_gain=moisture,
        oxygen_ppm=oxygen,
        fat_content_pct=fat,
        water_activity=aw,
        temperature_c=temperature_c,
    )

    metrics = stack_metrics(layers)
    recycle = recyclability_score(layers)
    predicted = float(result.predicted_shelf_life_days)
    compostable = any(find_material(material).compostable for material, _ in candidate.layers)

    payload = {
        # --- contract kept identical to the old templates ---
        "structure": metrics["structure"],
        "layers": metrics["layers"],
        "otr_cc_m2_day": metrics["otr_cc_m2_day"],
        "mvtr_g_m2_day": metrics["mvtr_g_m2_day"],
        "cost_per_1k": metrics["cost_per_1k"],
        "cost_per_unit": metrics["cost_per_unit"],
        "currency": metrics["currency"],
        "carbon_kgco2e_per_kg": metrics["carbon_kgco2e_per_kg"],
        "totalThicknessUm": metrics["totalThicknessUm"],
        # --- solver-derived, honest additions ---
        "meets_target": predicted + _TOLERANCE_DAYS >= target_days,
        "predicted_shelf_life_days": round(predicted, 1),
        "limiting_factor": result.limiting_factor,
        "target_shelf_life_days": round(target_days, 1),
        "recyclability_score": recycle["score"],
        "recyclability_grade": recycle["grade"],
        "distinct_material_count": len(recycle["distinctMaterials"]),
        "compostable": compostable,
        "within_budget": budget <= 0 or metrics["cost_per_1k"] <= budget,
        "why": _why(layers, result, target_days),
    }
    return _Evaluation(layers=layers, payload=payload)


def solve_recommendations(product: dict) -> dict:
    """Three tiers solved for this product.

    Returns a dict keyed ``cost_optimized`` / ``sustainability_first`` /
    ``max_barrier``, each holding the same field names the old templates used
    plus ``meets_target``, ``predicted_shelf_life_days``, ``limiting_factor``,
    ``target_shelf_life_days``, ``recyclability_score``, ``within_budget`` and a
    ``why`` list.

    When nothing in the search space holds the product for its target life, the
    closest stacks are returned with ``meets_target: False`` — the caller is
    expected to surface that rather than pretend otherwise.
    """
    target_days = float(product.get("targetShelfLifeDays") or 180)
    spec = category_spec(product.get("category"))

    # Storage temperature drives every rate. The band's midpoint is the honest
    # single point to integrate at.
    max_temp = float(product.get("maxTempC") or 25.0)
    min_temp = float(product.get("minTempC") or max_temp)
    temperature_c = (min_temp + max_temp) / 2.0

    humidity = float(product.get("relativeHumidityPct") or 60.0)
    fat = float(product.get("fatContent") or 0.0)
    aw = float(product.get("waterActivity") or 0.5)
    budget = float(product.get("budgetPer1kUnits") or 0.0)

    duration = max(target_days * _WINDOW_FACTOR, _MIN_WINDOW_DAYS)

    # Quality decay does not depend on the film, so integrate it once instead of
    # once per candidate (it is an ODE solve and dominates runtime).
    k, _kinetics = arrhenius.build_rate_constant(
        product.get("category"),
        temperature_c,
        int(target_days) or 1,
        spec.quality_threshold,
    )
    time_days, quality = arrhenius.integrate_quality(k, duration, n_points=_N_POINTS)

    evaluations = [
        _evaluate(
            candidate,
            product=product,
            time_days=time_days,
            quality=quality,
            duration=duration,
            temperature_c=temperature_c,
            humidity=humidity,
            fat=fat,
            aw=aw,
            target_days=target_days,
            budget=budget,
        )
        for candidate in _candidates()
    ]

    feasible = [e for e in evaluations if e.payload["meets_target"]]
    pool = feasible or evaluations
    budget_pool = [e for e in pool if e.payload["within_budget"]] or pool

    picks = {
        "cost_optimized": min(
            budget_pool,
            key=lambda e: (e.payload["cost_per_1k"], -e.payload["recyclability_score"]),
        ),
        "sustainability_first": max(
            pool,
            key=lambda e: (e.payload["recyclability_score"], -e.payload["cost_per_1k"]),
        ),
        "max_barrier": min(
            pool,
            key=lambda e: (e.payload["otr_cc_m2_day"], e.payload["mvtr_g_m2_day"]),
        ),
    }

    tiers: dict[str, dict] = {}
    for tier, evaluation in picks.items():
        payload = dict(evaluation.payload)
        payload["tier"] = tier
        payload["rationale"] = _TIER_RATIONALE[tier]
        tiers[tier] = payload
    return tiers
