"""Cost & sustainability LCA engine.

Mostly lookup-table math over ``material_db`` — deliberately simple and
consistent so every screen agrees. All factors are labelled "industry-average
estimates" in the API responses.
"""

from __future__ import annotations

from dataclasses import dataclass

from services.material_db import find_material
from services.permeability import LayerSpec, resolve_layers

#: Indian market currency — every monetary output is in INR (₹).
CURRENCY = {"code": "INR", "symbol": "\u20b9", "basis": "Indian market"}

#: fixed conversion (lamination + printing) cost, INR per m^2
EXTRUSION_RATE_PER_M2 = 4.5

#: INR per kg*km (Indian road/sea/air freight, indicative)
FREIGHT_RATE_PER_KG_KM = {
    "road": 0.0035,
    "sea": 0.0012,
    "air": 0.0280,
}

#: kgCO2e per tonne*km
FREIGHT_CO2_PER_TONNE_KM = {
    "road": 0.105,
    "sea": 0.016,
    "air": 0.602,
}

#: Illustrative extended-producer-responsibility plastic fee, INR per kg.
#: `IN` follows the Indian Plastic Waste Management EPR fee range for flexible
#: packaging; the other rows are INR equivalents for comparison only. Rates vary
#: by jurisdiction and change yearly — the UI must state the jurisdiction
#: explicitly and that these are indicative.
EPR_TAX_PER_KG = {
    "IN": 4.0,
    "EU": 70.0,
    "UK": 22.0,
    "US-CA": 12.0,
    "none": 0.0,
}

DEFAULT_JURISDICTION = "IN"

#: Substitutions used to build a suggested eco-stack for the EPR comparison.
ECO_SUBSTITUTE = {
    "pet": "nanocellulose",
    "met_pet": "nanocellulose",
    "evoh": "nanocellulose",
    "alox_pet": "nanocellulose",
    "alu_foil": "alox_pet",
    "ldpe": "pla",
    "hdpe": "pla",
    "pp": "pla",
    "bopp": "pla",
    "ionomer": "pla",
}


@dataclass
class LayerMass:
    key: str
    name: str
    thickness_um: float
    mass_kg: float
    material_cost: float
    carbon_kgco2e: float
    water_l: float
    plastic: bool
    compostable: bool
    landfill_years: float
    compost_months: float | None
    recyclability: float


def _layer_masses(layers: list, area_m2: float) -> list[LayerMass]:
    out: list[LayerMass] = []
    for layer in resolve_layers(layers):
        mat = layer.material
        mass = layer.thickness_um * 1e-3 * mat.density * area_m2  # kg
        out.append(
            LayerMass(
                key=mat.key,
                name=mat.name,
                thickness_um=layer.thickness_um,
                mass_kg=mass,
                material_cost=mass * mat.cost_per_kg,
                carbon_kgco2e=mass * mat.carbon_kgco2e_per_kg,
                water_l=mass * mat.water_l_per_kg,
                plastic=mat.plastic,
                compostable=mat.compostable,
                landfill_years=mat.landfill_years,
                compost_months=mat.compost_months,
                recyclability=mat.recyclability,
            )
        )
    return out


def cost_breakdown(
    layers: list,
    *,
    area_m2: float,
    units: int = 1000,
    distance_km: float = 0.0,
    freight_mode: str = "road",
    jurisdiction: str = DEFAULT_JURISDICTION,
) -> dict:
    """Per-unit and per-``units`` cost split for one packaging stack, in INR."""
    masses = _layer_masses(layers, area_m2)
    raw_material = sum(m.material_cost for m in masses)
    extrusion = EXTRUSION_RATE_PER_M2 * area_m2
    total_mass = sum(m.mass_kg for m in masses)
    mode = freight_mode if freight_mode in FREIGHT_RATE_PER_KG_KM else "road"
    transport = total_mass * distance_km * FREIGHT_RATE_PER_KG_KM[mode]
    plastic_mass = sum(m.mass_kg for m in masses if m.plastic)
    eol_tax = plastic_mass * EPR_TAX_PER_KG.get(jurisdiction, 0.0)

    per_unit = raw_material + extrusion + transport + eol_tax
    return {
        "currency": CURRENCY,
        "per_unit": {
            "rawMaterial": round(raw_material, 6),
            "extrusion": round(extrusion, 6),
            "transport": round(transport, 6),
            "eolDisposalTax": round(eol_tax, 6),
            "total": round(per_unit, 6),
        },
        "per_1k_units": {
            "rawMaterial": round(raw_material * units, 3),
            "extrusion": round(extrusion * units, 3),
            "transport": round(transport * units, 3),
            "eolDisposalTax": round(eol_tax * units, 3),
            "total": round(per_unit * units, 3),
        },
        "massPerUnitKg": round(total_mass, 6),
        "massPer1kUnitsKg": round(total_mass * units, 4),
        "plasticMassPerUnitKg": round(plastic_mass, 6),
        "distanceKm": distance_km,
        "freightMode": mode,
        "jurisdiction": jurisdiction,
        "assumptions": (
            "Indian-market film prices (INR/kg) and an illustrative EPR fee rate."
        ),
    }


def carbon_footprint(
    layers: list,
    *,
    area_m2: float,
    units: int = 1000,
    distance_km: float = 0.0,
    freight_mode: str = "road",
) -> dict:
    masses = _layer_masses(layers, area_m2)
    material_carbon = sum(m.carbon_kgco2e for m in masses)
    total_mass = sum(m.mass_kg for m in masses)
    mode = freight_mode if freight_mode in FREIGHT_CO2_PER_TONNE_KM else "road"
    transport_carbon = total_mass * distance_km * FREIGHT_CO2_PER_TONNE_KM[mode] / 1000.0
    per_unit = material_carbon + transport_carbon
    return {
        "material_kgco2e_per_unit": round(material_carbon, 6),
        "transport_kgco2e_per_unit": round(transport_carbon, 6),
        "kgco2e_per_unit": round(per_unit, 6),
        "carbonFootprintKgCO2e": round(per_unit * units, 4),
        "by_material": [
            {"material": m.name, "kgco2e_per_unit": round(m.carbon_kgco2e, 6)}
            for m in masses
        ],
        "assumptions": "Cradle-to-gate industry averages; transport is tonne-km based.",
    }


def water_usage(layers: list, *, area_m2: float, units: int = 1000) -> dict:
    masses = _layer_masses(layers, area_m2)
    per_unit = sum(m.water_l for m in masses)
    return {
        "water_l_per_unit": round(per_unit, 6),
        "waterUsageL": round(per_unit * units, 3),
        "by_material": [
            {"material": m.name, "litres_per_unit": round(m.water_l, 6)} for m in masses
        ],
    }


def recyclability_score(layers: list, area_m2: float = 1.0) -> dict:
    """0-100 score.

    ``base`` is the mass-weighted material recyclability. Then:
    * mono-material stacks (one material key) get +10
    * each layer beyond two costs -5 (harder to separate)
    * any compostable component gets +8
    """
    masses = _layer_masses(layers, area_m2)
    if not masses:
        return {"score": 0.0, "grade": "F", "factors": {}}
    total = sum(m.mass_kg for m in masses) or 1.0
    base = sum((m.mass_kg / total) * m.recyclability for m in masses)

    distinct = {m.key for m in masses}
    mono = len(distinct) == 1
    layer_penalty = max(0, len(masses) - 2) * 5.0
    compostable = any(m.compostable for m in masses)

    score = base + (10.0 if mono else 0.0) + (8.0 if compostable else 0.0) - layer_penalty
    score = max(0.0, min(100.0, score))
    grade = "A" if score >= 80 else "B" if score >= 65 else "C" if score >= 50 else "D" if score >= 35 else "F"
    return {
        "score": round(score, 1),
        "grade": grade,
        "factors": {
            "massWeightedBase": round(base, 1),
            "monoMaterial": mono,
            "monoMaterialBonus": 10.0 if mono else 0.0,
            "layerCountPenalty": -layer_penalty,
            "compostableBonus": 8.0 if compostable else 0.0,
        },
        "distinctMaterials": sorted(distinct),
        "assumptions": "Mono-material and compostable stacks score higher by design.",
    }


def degradation_timeline(layers: list, area_m2: float = 1.0) -> dict:
    masses = _layer_masses(layers, area_m2)
    if not masses:
        return {"landfill_years": 0.0, "compost_months": None, "by_material": []}
    heaviest = max(masses, key=lambda m: m.mass_kg)
    compostables = [m.compost_months for m in masses if m.compost_months is not None]
    return {
        "landfill_years": round(max(m.landfill_years for m in masses), 1),
        "dominant_material": heaviest.name,
        "compost_months": None if not compostables else round(max(compostables), 1),
        "fully_compostable": all(m.compostable for m in masses),
        "by_material": [
            {
                "material": m.name,
                "landfill_years": m.landfill_years,
                "compost_months": m.compost_months,
            }
            for m in masses
        ],
    }


def eco_stack_suggestion(layers: list) -> list[dict]:
    """Swap high-impact layers for lower-impact alternatives (same thickness)."""
    out: list[dict] = []
    for layer in resolve_layers(layers):
        substitute = ECO_SUBSTITUTE.get(layer.material.key, layer.material.key)
        out.append({"material": substitute, "thicknessUm": layer.thickness_um})
    return out


def epr_tax_comparison(
    layers: list,
    *,
    area_m2: float,
    units: int = 1000,
    jurisdiction: str = DEFAULT_JURISDICTION,
) -> dict:
    """Current-stack plastic fee vs a suggested eco-stack, in INR."""
    rate = EPR_TAX_PER_KG.get(jurisdiction, 0.0)
    current_masses = _layer_masses(layers, area_m2)
    current_plastic = sum(m.mass_kg for m in current_masses if m.plastic)
    current_tax = current_plastic * rate * units

    eco_layers = eco_stack_suggestion(layers)
    eco_masses = _layer_masses(eco_layers, area_m2)
    eco_plastic = sum(m.mass_kg for m in eco_masses if m.plastic)
    eco_tax = eco_plastic * rate * units

    saving = current_tax - eco_tax
    pct = (saving / current_tax * 100.0) if current_tax > 0 else 0.0
    return {
        "currency": CURRENCY,
        "jurisdiction": jurisdiction,
        "ratePerKg": rate,
        "current": {
            "plasticMassKg": round(current_plastic * units, 4),
            "taxPer1kUnits": round(current_tax, 3),
        },
        "ecoStack": {
            "layers": eco_layers,
            "plasticMassKg": round(eco_plastic * units, 4),
            "taxPer1kUnits": round(eco_tax, 3),
        },
        "savingPer1kUnits": round(saving, 3),
        "savingPercent": round(pct, 1),
        "disclaimer": (
            "Indicative rates only — EPR rules and rates differ by jurisdiction."
        ),
    }
