"""Shelf-life prediction: moisture, oxidation and microbial spoilage models.

Extends the Arrhenius quality model in ``arrhenius.py`` with three independent
failure modes, each evaluated on the same simulated timeline:

* **Moisture gain** — Fickian approximation, cumulative g/m^2 vs a per-category
  critical moisture value (texture / crispness loss).
* **Peroxide value (PV)** — first-order oxidation kinetics driven by fat
  content, temperature and cumulative oxygen exposure.
* **Microbial growth** — logistic curve, growth rate scaled by water activity
  and temperature (simplified Q10 + aw model, disclosed as such).

The prediction is the *earliest* of: quality threshold crossing, moisture
critical day and the microbial limit — whichever fails first.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

from services.categories import normalize_category


@dataclass(frozen=True)
class CategorySpec:
    category: str
    #: quality % below which the product is off-spec
    quality_threshold: float
    #: g/m^2 absorbed before texture/acceptability loss
    critical_moisture_g_m2: float
    #: initial peroxide value, meq O2/kg
    pv0: float
    #: rancidity limit, meq O2/kg
    pv_limit: float
    #: log10 CFU/g at t=0
    initial_log_cfu: float
    #: spoilage limit, log10 CFU/g
    critical_log_cfu: float
    #: baseline growth rate r at aw=0.99, 25 degC (per day)
    microbial_r_ref: float
    #: equilibrium relative humidity (%) inside the pack at rest
    equilibrium_rh_pct: float
    notes: str = ""


def _spec(
    category: str,
    *,
    quality_threshold: float = 70.0,
    critical_moisture_g_m2: float,
    pv0: float,
    pv_limit: float,
    initial_log_cfu: float,
    critical_log_cfu: float,
    microbial_r_ref: float,
    equilibrium_rh_pct: float,
    notes: str = "",
) -> CategorySpec:
    return CategorySpec(
        category,
        quality_threshold,
        critical_moisture_g_m2,
        pv0,
        pv_limit,
        initial_log_cfu,
        critical_log_cfu,
        microbial_r_ref,
        equilibrium_rh_pct,
        notes,
    )


# Critical values are engineering rules of thumb per food family, kept as
# explicit constants so they can be defended in a Q&A.
CATEGORY_SPECS: dict[str, CategorySpec] = {
    "snacks": _spec(
        "snacks",
        critical_moisture_g_m2=3.0,
        pv0=0.5,
        pv_limit=10.0,
        initial_log_cfu=1.5,
        critical_log_cfu=4.0,
        microbial_r_ref=0.02,
        equilibrium_rh_pct=20.0,
        notes="Crispness is lost above a few g/m^2 moisture; lipid oxidation dominates.",
    ),
    "dairy": _spec(
        "dairy",
        critical_moisture_g_m2=1.0,
        pv0=1.0,
        pv_limit=8.0,
        initial_log_cfu=3.0,
        critical_log_cfu=6.0,
        microbial_r_ref=0.30,
        equilibrium_rh_pct=90.0,
        notes="High aw — psychrotrophic growth rate dominates at chilled temperatures.",
    ),
    "fruitsVegetables": _spec(
        "fruitsVegetables",
        critical_moisture_g_m2=25.0,
        pv0=0.2,
        pv_limit=6.0,
        initial_log_cfu=3.5,
        critical_log_cfu=7.0,
        microbial_r_ref=0.25,
        equilibrium_rh_pct=97.0,
        notes="Breathable films — moisture loss (not gain) and mould are key.",
    ),
    "meatSeafood": _spec(
        "meatSeafood",
        critical_moisture_g_m2=3.0,
        pv0=1.5,
        pv_limit=9.0,
        initial_log_cfu=2.5,
        critical_log_cfu=6.0,
        microbial_r_ref=0.35,
        equilibrium_rh_pct=99.0,
        notes="Oxidation drives colour/bloom loss; pathogen growth sets the limit.",
    ),
    "bakery": _spec(
        "bakery",
        critical_moisture_g_m2=5.0,
        pv0=0.4,
        pv_limit=8.0,
        initial_log_cfu=2.0,
        critical_log_cfu=5.0,
        microbial_r_ref=0.08,
        equilibrium_rh_pct=70.0,
        notes="Moisture migration causes staling; mould at higher aw.",
    ),
    "beverages": _spec(
        "beverages",
        critical_moisture_g_m2=2.0,
        pv0=0.1,
        pv_limit=5.0,
        initial_log_cfu=1.0,
        critical_log_cfu=4.0,
        microbial_r_ref=0.15,
        equilibrium_rh_pct=95.0,
        notes="Aseptic filling shifts the limit to vitamin/aroma degradation.",
    ),
    "readyToEat": _spec(
        "readyToEat",
        critical_moisture_g_m2=4.0,
        pv0=1.0,
        pv_limit=9.0,
        initial_log_cfu=2.5,
        critical_log_cfu=6.0,
        microbial_r_ref=0.18,
        equilibrium_rh_pct=92.0,
        notes="Mixed system — keep both moisture and microbial limits in view.",
    ),
    "grainsPulses": _spec(
        "grainsPulses",
        critical_moisture_g_m2=8.0,
        pv0=0.3,
        pv_limit=8.0,
        initial_log_cfu=1.5,
        critical_log_cfu=5.0,
        microbial_r_ref=0.03,
        equilibrium_rh_pct=60.0,
        notes="Mould/insect activity and moisture regain above ~60% ERH.",
    ),
    "others": _spec(
        "others",
        critical_moisture_g_m2=4.0,
        pv0=0.5,
        pv_limit=8.0,
        initial_log_cfu=2.0,
        critical_log_cfu=5.0,
        microbial_r_ref=0.10,
        equilibrium_rh_pct=75.0,
    ),
}


def category_spec(category: str | None) -> CategorySpec:
    key = normalize_category(category)
    return CATEGORY_SPECS.get(key, CATEGORY_SPECS["others"])


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


#: Food families that are wet by definition. Their water activity sits close to
#: that of pure water regardless of a measured moisture content.
_PERISHABLE_CATEGORIES = frozenset(
    {"dairy", "beverages", "meatSeafood", "readyToEat", "fruitsVegetables"}
)


def estimate_water_activity(
    category: str | None, moisture_pct: float = 0.0
) -> float:
    """Approximate water activity when the client did not measure it.

    The product wizard collects moisture content, not Aw, so perishable
    families are pinned near 1.0 and dry / semi-dry families are mapped from
    their moisture content. This is an explicit approximation: prefer a
    measured value whenever the client can supply one.
    """
    if normalize_category(category) in _PERISHABLE_CATEGORIES:
        return 0.97
    return clamp(0.20 + (moisture_pct or 0.0) * 0.03, 0.10, 0.95)


# ---------------------------------------------------------------------------
# Moisture
# ---------------------------------------------------------------------------
#: MVTR is quoted at the standard 38 degC / 90% RH test condition.
MVTR_REFERENCE_TEMP_C = 38.0


def moisture_gain_curve(
    mvtr_g_m2_day: float,
    rh_outside_pct: float,
    rh_inside_pct: float,
    duration_days: float,
    n_points: int = 61,
    temperature_c: float = MVTR_REFERENCE_TEMP_C,
) -> list[float]:
    """Cumulative moisture gain (g/m^2) — simple Fickian approximation.

    Driving force is the vapour-pressure difference across the film, expressed
    here as a normalised RH gradient. The stack MVTR is referenced to 38 degC and
    scaled with a Q10=2 temperature response, so cold-chain runs absorb moisture
    far more slowly than tropical ones. Listed as "simplified Fickian" in the UI.
    """
    driving = (rh_outside_pct - rh_inside_pct) / 100.0
    temp_factor = clamp(
        2.0 ** ((temperature_c - MVTR_REFERENCE_TEMP_C) / 10.0), 0.02, 8.0
    )
    flux = max(mvtr_g_m2_day, 0.0) * max(driving, 0.0) * temp_factor
    if duration_days <= 0:
        return [0.0]
    return [flux * (duration_days * i / (n_points - 1)) for i in range(n_points)]


def first_crossing(time_days: list[float], values: list[float], limit: float) -> float | None:
    """First time the series reaches ``limit`` (linear interpolation)."""
    for i, value in enumerate(values):
        if value >= limit:
            if i == 0:
                return time_days[0]
            prev_value, prev_time = values[i - 1], time_days[i - 1]
            span = value - prev_value
            frac = 0.0 if span <= 0 else (limit - prev_value) / span
            return prev_time + frac * (time_days[i] - prev_time)
    return None


# ---------------------------------------------------------------------------
# Oxidation / peroxide value
# ---------------------------------------------------------------------------
def peroxide_value_curve(
    spec: CategorySpec,
    fat_content_pct: float,
    temperature_c: float,
    time_days: list[float],
    oxygen_ppm: list[float],
) -> list[float]:
    """PV(t) = PV0 + k_ox * (cumulative O2 exposure / 1e6).

    ``k_ox`` scales with fat content and follows a Q10=2 temperature response
    relative to 25 degC. Exposure is integrated with the trapezoid rule over the
    simulated oxygen headspace curve; dividing by 1e6 converts ppm*day into
    fraction*day so ``k_ox`` stays in a physical meq O2/kg per unit range.
    """
    k_ox = 0.16 * (0.5 + fat_content_pct / 20.0) * (2.0 ** ((temperature_c - 25.0) / 10.0))
    cumulative = 0.0
    curve: list[float] = []
    for i, t in enumerate(time_days):
        if i > 0:
            dt = t - time_days[i - 1]
            cumulative += 0.5 * (oxygen_ppm[i] + oxygen_ppm[i - 1]) * dt
        curve.append(spec.pv0 + k_ox * cumulative / 1e6)
    return curve


# ---------------------------------------------------------------------------
# Microbial growth
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Oxygen consumption in the headspace
# ---------------------------------------------------------------------------
def oxygen_consumption_ppm_per_day(
    fat_content_pct: float,
    temperature_c: float,
) -> float:
    """Headspace O2 consumed by oxidation, in ppm/day.

    Scales with fat content and follows the same Q10=2 temperature response as
    the peroxide model. Combined with ingress through the film this is what makes
    a high-barrier stack actually keep headspace oxygen low.
    """
    temp_factor = clamp(2.0 ** ((temperature_c - 25.0) / 10.0), 0.02, 8.0)
    return 1200.0 * (0.3 + fat_content_pct / 20.0) * temp_factor


def microbial_growth_rate(spec: CategorySpec, water_activity: float, temperature_c: float) -> float:
    """r = r_ref * aw_factor * Q10 temperature factor."""
    aw_factor = clamp((water_activity - 0.80) / (0.99 - 0.80), 0.02, 1.0)
    temp_factor = clamp(2.0 ** ((temperature_c - 25.0) / 10.0), 0.02, 8.0)
    return spec.microbial_r_ref * aw_factor * temp_factor


def microbial_curve(
    spec: CategorySpec,
    water_activity: float,
    temperature_c: float,
    time_days: list[float],
    n_cap_log: float = 9.0,
) -> list[float]:
    """Logistic growth curve, reported as log10 CFU/g.

    ``N(t) = N0 * exp(r t) / (1 + N0 * (exp(r t) - 1) / Ncap)``
    """
    r = microbial_growth_rate(spec, water_activity, temperature_c)
    n0 = 10.0 ** spec.initial_log_cfu
    n_cap = 10.0 ** n_cap_log
    out: list[float] = []
    for t in time_days:
        growth = math.exp(min(r * t, 60.0))
        n_t = n0 * growth / (1.0 + n0 * (growth - 1.0) / n_cap)
        out.append(math.log10(max(n_t, 1e-6)))
    return out


# ---------------------------------------------------------------------------
# Combined prediction
# ---------------------------------------------------------------------------
@dataclass
class ShelfLifeResult:
    predicted_shelf_life_days: float
    limiting_factor: str
    moisture_critical_day: float | None
    pv_limit_day: float | None
    microbial_limit_day: float | None
    quality_threshold_day: float | None
    threshold_used: float
    spec: CategorySpec = field(repr=False)


def predict_shelf_life(
    *,
    category: str | None,
    time_days: list[float],
    quality: list[float],
    moisture_gain: list[float],
    oxygen_ppm: list[float],
    fat_content_pct: float,
    water_activity: float,
    temperature_c: float,
    quality_threshold: float | None = None,
) -> ShelfLifeResult:
    spec = category_spec(category)
    threshold = quality_threshold if quality_threshold is not None else spec.quality_threshold

    # Quality decays downward -> find first crossing below the threshold.
    quality_day: float | None = None
    for i, q in enumerate(quality):
        if q < threshold:
            if i == 0:
                quality_day = time_days[0]
            else:
                prev_q = quality[i - 1]
                span = prev_q - q
                frac = 0.0 if span <= 0 else (prev_q - threshold) / span
                quality_day = time_days[i - 1] + frac * (time_days[i] - time_days[i - 1])
            break

    moisture_day = first_crossing(time_days, moisture_gain, spec.critical_moisture_g_m2)
    pv = peroxide_value_curve(spec, fat_content_pct, temperature_c, time_days, oxygen_ppm)
    pv_day = first_crossing(time_days, pv, spec.pv_limit)
    micro = microbial_curve(spec, water_activity, temperature_c, time_days)
    micro_day = first_crossing(time_days, micro, spec.critical_log_cfu)

    candidates = {
        "quality": quality_day,
        "moisture": moisture_day,
        "oxidation": pv_day,
        "microbial": micro_day,
    }
    present = {k: v for k, v in candidates.items() if v is not None}
    if present:
        limiting = min(present, key=lambda k: present[k])
        predicted = present[limiting]
    else:
        limiting = "none"
        predicted = time_days[-1] if time_days else 0.0

    return ShelfLifeResult(
        predicted_shelf_life_days=round(predicted, 1),
        limiting_factor=limiting,
        moisture_critical_day=None if moisture_day is None else round(moisture_day, 1),
        pv_limit_day=None if pv_day is None else round(pv_day, 1),
        microbial_limit_day=None if micro_day is None else round(micro_day, 1),
        quality_threshold_day=None if quality_day is None else round(quality_day, 1),
        threshold_used=threshold,
        spec=spec,
    )
