"""Digital Twin simulation engine.

Produces the three time series the charts consume:

* ``quality``            — Arrhenius first-order decay (``scipy.solve_ivp``)
* ``moisture_gain_g_m2`` — Fickian moisture uptake, driven by the stack MVTR
* ``oxygen_accum_ppm``   — first-order approach of headspace O2 to ambient (21%)

All three are real formulas over ``material_db`` data — no LLM involved.
"""

from __future__ import annotations

import math

from services import arrhenius, shelf_life
from services.categories import normalize_category
from services.fallback import RECOMMENDATION_TEMPLATES
from services.permeability import series_transmission

#: Assumed headspace volume per m^2 of film (metres-free lumped constant used to
#: convert cc/m^2/day ingress into headspace ppm).
HEADSPACE_L_PER_M2 = 1.0

#: Ambient oxygen fraction in air.
AMBIENT_O2_FRACTION = 0.21

CATEGORY_DEFAULT_STACK: dict[str, list[dict]] = {
    "snacks": RECOMMENDATION_TEMPLATES["cost_optimized"],
    "dairy": RECOMMENDATION_TEMPLATES["max_barrier"],
    "fruitsVegetables": RECOMMENDATION_TEMPLATES["sustainability_first"],
    "meatSeafood": RECOMMENDATION_TEMPLATES["max_barrier"],
    "bakery": RECOMMENDATION_TEMPLATES["cost_optimized"],
    "beverages": RECOMMENDATION_TEMPLATES["max_barrier"],
    "readyToEat": RECOMMENDATION_TEMPLATES["max_barrier"],
    "grainsPulses": RECOMMENDATION_TEMPLATES["cost_optimized"],
    "others": RECOMMENDATION_TEMPLATES["cost_optimized"],
}

ASSUMPTIONS = [
    "Quality decay: first-order Arrhenius kinetics, calibrated so the label "
    "claim is met at 25 degC.",
    "Moisture: simplified Fickian uptake from stack MVTR, the RH gradient and a "
    "Q10=2 temperature response (MVTR referenced to 38 degC).",
    "Oxygen: headspace balance of ingress through the film against product "
    "consumption, so a high-barrier stack keeps headspace O2 low.",
    "Activation energies and permeabilities are typical published ranges, not "
    "proprietary lab data.",
]


def resolve_simulation_stack(product: dict, request) -> list[dict]:
    """Pick the layer stack and apply the barrier-thickness control.

    If the client sends no explicit stack we use the category default, then
    scale every layer by ``barrierThicknessUm / totalThickness`` so the
    "barrier thickness" slider still has a physically meaningful effect.
    """
    layers = list(request.layers or [])
    if not layers:
        base = CATEGORY_DEFAULT_STACK.get(
            normalize_category(product.get("category")),
            CATEGORY_DEFAULT_STACK["others"],
        )
        layers = [dict(layer) for layer in base]

    thickness = request.barrierThicknessUm
    if thickness and thickness > 0:
        total = sum(layer.get("thicknessUm", 0) or 0 for layer in layers)
        if total > 0:
            scale = thickness / total
            layers = [
                {
                    **layer,
                    "thicknessUm": max(float(layer.get("thicknessUm", 0)) * scale, 0.5),
                }
                for layer in layers
            ]
    return layers


def oxygen_accumulation(
    *,
    otr: float,
    o2_start_fraction: float,
    duration_days: float,
    n_points: int,
    temperature_c: float,
    fat_content_pct: float,
) -> list[float]:
    """Headspace O2 (ppm) from a balance of film ingress and product consumption.

    dO2/dt = k_in * (O2_ambient - O2) - consumption, integrated numerically and
    clamped at zero. With a strong barrier (low ``otr``) and a fatty product the
    headspace is scrubbed to near zero; with a poor barrier it stays at ambient.
    """
    ambient_ppm = AMBIENT_O2_FRACTION * 1e6
    #: ppm/day per ppm of driving force (0.79 cc/m2/day into 1 L/m2 headspace
    #: is a ~166 ppm/day exchange at a full 21% gradient).
    ingress = max(otr, 0.0) / 1000.0
    consumption = shelf_life.oxygen_consumption_ppm_per_day(
        fat_content_pct, temperature_c
    )

    current = o2_start_fraction * 1e6
    if duration_days <= 0 or n_points < 2:
        return [current]

    interval = duration_days / (n_points - 1)
    out = [current]

    if ingress <= 0:
        # No replenishment: the product can only scrub what is already there.
        for _ in range(n_points - 1):
            current = max(0.0, current - consumption * interval)
            out.append(current)
        return out

    # Exact solution of dO2/dt = ingress*(ambient - O2) - consumption per step,
    # so the integration is stable for any step size.
    equilibrium = ambient_ppm - consumption / ingress
    decay = math.exp(-ingress * interval)
    for _ in range(n_points - 1):
        current = max(0.0, equilibrium + (current - equilibrium) * decay)
        out.append(current)
    return out


def _quality_at(points: list[float], qualities: list[float], day: float) -> float:
    if not points:
        return 0.0
    if day <= points[0]:
        return qualities[0]
    if day >= points[-1]:
        return qualities[-1]
    for i in range(1, len(points)):
        if points[i] >= day:
            span = points[i] - points[i - 1]
            frac = 0.0 if span == 0 else (day - points[i - 1]) / span
            return qualities[i - 1] + frac * (qualities[i] - qualities[i - 1])
    return qualities[-1]


def run_simulation(product: dict, request, n_points: int = 61) -> dict:
    """Compute the full simulation result. ``request`` must be a resolved
    ``SimulationRequest`` (chamber defaults applied)."""
    layers = resolve_simulation_stack(product, request)
    permeability = series_transmission(layers)

    duration = max(float(request.durationDays or 180.0), 0.0)
    temperature = float(request.temperatureC)
    humidity = float(request.humidityRH)
    gas = request.gasMix
    gas_mix = {
        "o2": float(gas.o2),
        "co2": float(gas.co2),
        "n2": float(gas.n2),
    } if gas else {"o2": 21.0, "co2": 0.0, "n2": 79.0}

    spec = shelf_life.category_spec(product.get("category"))

    # ---- 1. Quality decay (Arrhenius + solve_ivp) -------------------------
    k, kinetics = arrhenius.build_rate_constant(
        product.get("category"),
        temperature,
        float(product.get("targetShelfLifeDays") or 90),
        spec.quality_threshold,
    )
    time_days, quality = arrhenius.integrate_quality(k, duration, n_points=n_points)

    # ---- 2. Moisture gain (Fickian approximation) -------------------------
    moisture = shelf_life.moisture_gain_curve(
        permeability.mvtr,
        humidity,
        spec.equilibrium_rh_pct,
        duration,
        n_points=n_points,
        temperature_c=temperature,
    )

    # ---- 3. Oxygen accumulation (ingress vs. product consumption) ---------
    oxygen = oxygen_accumulation(
        otr=permeability.otr,
        o2_start_fraction=gas_mix["o2"] / 100.0,
        duration_days=duration,
        n_points=n_points,
        temperature_c=temperature,
        fat_content_pct=float(product.get("fatContent") or 0.0),
    )

    final_quality = quality[-1] if quality else 0.0
    if final_quality > 80:
        status = "Optimal"
    elif final_quality >= 50:
        status = "Warning"
    else:
        status = "Action Needed"

    return {
        "layers": layers,
        "permeability": permeability,
        "kinetics": kinetics,
        "k": k,
        "spec": spec,
        "status": status,
        "finalQuality": round(final_quality, 2),
        "time_days": time_days,
        "quality": quality,
        "moisture_gain_g_m2": moisture,
        "oxygen_accum_ppm": oxygen,
        "temperatureC": temperature,
        "humidityRH": humidity,
        "gasMix": gas_mix,
        "durationDays": duration,
        "barrierThicknessUm": permeability.total_thickness_um,
    }


def build_shelf_life(product: dict, request, n_points: int = 61) -> dict:
    """Shelf-life prediction reusing the simulation curves."""
    sim = run_simulation(product, request, n_points=n_points)
    result = shelf_life.predict_shelf_life(
        category=product.get("category"),
        time_days=sim["time_days"],
        quality=sim["quality"],
        moisture_gain=sim["moisture_gain_g_m2"],
        oxygen_ppm=sim["oxygen_accum_ppm"],
        fat_content_pct=float(product.get("fatContent") or 0.0),
        water_activity=float(product.get("waterActivity") or 0.5),
        temperature_c=sim["temperatureC"],
        quality_threshold=getattr(request, "qualityThreshold", None),
    )

    pv_curve = shelf_life.peroxide_value_curve(
        result.spec,
        float(product.get("fatContent") or 0.0),
        sim["temperatureC"],
        sim["time_days"],
        sim["oxygen_accum_ppm"],
    )
    microbial = shelf_life.microbial_curve(
        result.spec,
        float(product.get("waterActivity") or 0.5),
        sim["temperatureC"],
        sim["time_days"],
    )

    return {
        "sim": sim,
        "shelfLife": result,
        "pvCurve": pv_curve,
        "microbialCurve": microbial,
    }
