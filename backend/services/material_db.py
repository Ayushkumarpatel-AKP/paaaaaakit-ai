"""Material property database — the single source of truth.

Shared by the Digital Twin simulator, the 3D layer-stack customizer and the
LCA / cost engine so numbers never drift between screens.

COSTS are **Indian market prices in INR (₹ per kg)**, covering typical
converted/printed film rates (not raw resin). Keep them in ₹ so every screen
prices for the Indian market consistently; the carbon and water factors stay
physical (per kg) and are market-independent.

UNITS (chosen so the series-permeability math is unit-safe):

* ``otr``   — oxygen transmission as ``cc * um / (m^2 * day * atm)``
* ``mvtr``  — water-vapour transmission as ``g * um / (m^2 * day)``
* ``co2tr`` — CO2 transmission as ``cc * um / (m^2 * day * atm)``

Intrinsic permeability is stored as transmission-rate x thickness, so a layer
of thickness ``d`` (microns) has ``TR = P / d``. Resistances add in series::

    1 / TR_total = sum(d_i / P_i)

All integers below are **typical values from published packaging-literature
ranges**, not proprietary lab measurements. Disclose that in the UI.
"""

from __future__ import annotations

from dataclasses import dataclass, asdict
from typing import Iterable


@dataclass(frozen=True)
class Material:
    key: str
    name: str
    #: g/cm^3
    density: float
    #: INR per kg — indicative Indian-market converted-film price (₹/kg)
    cost_per_kg: float
    #: cc*um/(m^2*day*atm)
    otr: float
    #: g*um/(m^2*day)
    mvtr: float
    #: cc*um/(m^2*day*atm)
    co2tr: float
    #: cradle-to-gate kgCO2e per kg (industry average estimate)
    carbon_kgco2e_per_kg: float
    #: litres of water per kg
    water_l_per_kg: float
    #: years to degrade in landfill
    landfill_years: float
    #: months to industrial compost (None = not compostable)
    compost_months: float | None
    #: 0-100 recyclability of the material in isolation
    recyclability: float
    compostable: bool
    plastic: bool
    aliases: tuple[str, ...] = ()

    def as_dict(self) -> dict:
        d = asdict(self)
        # `aliases` stays internal but exposing it is harmless; keep it for the
        # /materials debug endpoint.
        return d


# ---------------------------------------------------------------------------
# The table. Keys are stable identifiers used throughout the backend.
# ---------------------------------------------------------------------------
MATERIALS: dict[str, Material] = {
    "pet": Material(
        key="pet",
        name="PET (Polyethylene Terephthalate)",
        density=1.38,
        cost_per_kg=220.0,
        otr=1200.0,
        mvtr=180.0,
        co2tr=4000.0,
        carbon_kgco2e_per_kg=2.9,
        water_l_per_kg=15.0,
        landfill_years=450.0,
        compost_months=None,
        recyclability=85.0,
        compostable=False,
        plastic=True,
        aliases=("pet", "polyethyleneterephthalate", "polyester"),
    ),
    "met_pet": Material(
        key="met_pet",
        name="Metallized PET",
        density=1.40,
        cost_per_kg=300.0,
        otr=9.6,
        mvtr=1.8,
        co2tr=60.0,
        carbon_kgco2e_per_kg=3.4,
        water_l_per_kg=40.0,
        landfill_years=450.0,
        compost_months=None,
        recyclability=55.0,
        compostable=False,
        plastic=True,
        aliases=("metallizedpet", "metpet", "metpet12", "metallisedpet", "mpet"),
    ),
    "ldpe": Material(
        key="ldpe",
        name="LDPE / PE sealant",
        density=0.92,
        cost_per_kg=190.0,
        otr=162500.0,
        mvtr=425.0,
        co2tr=500000.0,
        carbon_kgco2e_per_kg=1.9,
        water_l_per_kg=12.0,
        landfill_years=500.0,
        compost_months=None,
        recyclability=90.0,
        compostable=False,
        plastic=True,
        aliases=(
            "lowdensitypolyethylene",
            "ldpe",
            "pe",
            "polyethylene",
            "polythene",
        ),
    ),
    "hdpe": Material(
        key="hdpe",
        name="HDPE",
        density=0.95,
        cost_per_kg=185.0,
        otr=55000.0,
        mvtr=125.0,
        co2tr=180000.0,
        carbon_kgco2e_per_kg=1.8,
        water_l_per_kg=10.0,
        landfill_years=500.0,
        compost_months=None,
        recyclability=95.0,
        compostable=False,
        plastic=True,
        aliases=("highdensitypolyethylene", "hdpe"),
    ),
    "bopp": Material(
        key="bopp",
        name="BOPP (biaxially oriented PP)",
        density=0.905,
        cost_per_kg=205.0,
        otr=45000.0,
        mvtr=126.0,
        co2tr=150000.0,
        carbon_kgco2e_per_kg=2.0,
        water_l_per_kg=12.0,
        landfill_years=450.0,
        compost_months=None,
        recyclability=80.0,
        compostable=False,
        plastic=True,
        aliases=("bopp", "orientedpolypropylene", "biaxiallyoriented"),
    ),
    "pp": Material(
        key="pp",
        name="PP (Polypropylene)",
        density=0.905,
        cost_per_kg=195.0,
        otr=55000.0,
        mvtr=125.0,
        co2tr=180000.0,
        carbon_kgco2e_per_kg=2.0,
        water_l_per_kg=12.0,
        landfill_years=450.0,
        compost_months=None,
        recyclability=80.0,
        compostable=False,
        plastic=True,
        aliases=("polypropylene", "pp"),
    ),
    "alu_foil": Material(
        key="alu_foil",
        name="Aluminium foil",
        density=2.70,
        cost_per_kg=340.0,
        otr=0.07,
        mvtr=0.035,
        co2tr=0.05,
        carbon_kgco2e_per_kg=9.0,
        water_l_per_kg=30.0,
        landfill_years=200.0,
        compost_months=None,
        recyclability=70.0,
        compostable=False,
        plastic=False,
        aliases=("aluminiumfoil", "aluminumfoil", "alufoil", "alu", "aluminium", "aluminum", "foil"),
    ),
    "evoh": Material(
        key="evoh",
        name="EVOH (ethylene vinyl alcohol)",
        density=1.20,
        cost_per_kg=480.0,
        otr=6.0,
        mvtr=600.0,
        co2tr=20.0,
        carbon_kgco2e_per_kg=3.5,
        water_l_per_kg=25.0,
        landfill_years=450.0,
        compost_months=None,
        recyclability=40.0,
        compostable=False,
        plastic=True,
        aliases=("evoh", "ethylenevinylalcohol"),
    ),
    "alox_pet": Material(
        key="alox_pet",
        name="AlOx-coated PET",
        density=1.40,
        cost_per_kg=290.0,
        otr=7.2,
        mvtr=18.0,
        co2tr=45.0,
        carbon_kgco2e_per_kg=3.2,
        water_l_per_kg=35.0,
        landfill_years=450.0,
        compost_months=None,
        recyclability=65.0,
        compostable=False,
        plastic=True,
        aliases=("aloxcoatedpet", "alox", "aloxpet"),
    ),
    "pla": Material(
        key="pla",
        name="PLA (polylactic acid, compostable)",
        density=1.24,
        cost_per_kg=320.0,
        otr=30000.0,
        mvtr=2250.0,
        co2tr=90000.0,
        carbon_kgco2e_per_kg=0.8,
        water_l_per_kg=40.0,
        landfill_years=2.0,
        compost_months=6.0,
        recyclability=60.0,
        compostable=True,
        plastic=True,
        aliases=("polylacticacid", "pla", "bioplastic"),
    ),
    "nanocellulose": Material(
        key="nanocellulose",
        name="Nanocellulose coating",
        density=1.50,
        cost_per_kg=750.0,
        otr=200.0,
        mvtr=2000.0,
        co2tr=600.0,
        carbon_kgco2e_per_kg=0.4,
        water_l_per_kg=60.0,
        landfill_years=1.0,
        compost_months=3.0,
        recyclability=70.0,
        compostable=True,
        plastic=False,
        aliases=("nanocellulose", "cellulose", "mfc", "cnf"),
    ),
    "paperboard": Material(
        key="paperboard",
        name="Paperboard",
        density=0.70,
        cost_per_kg=75.0,
        otr=4.4e6,
        mvtr=110000.0,
        co2tr=6.0e6,
        carbon_kgco2e_per_kg=0.9,
        water_l_per_kg=20.0,
        landfill_years=2.0,
        compost_months=6.0,
        recyclability=90.0,
        compostable=True,
        plastic=False,
        aliases=("paperboard", "cardboard", "fscpaperboard", "paper"),
    ),
    "ionomer": Material(
        key="ionomer",
        name="Ionomer (Surlyn-type)",
        density=0.94,
        cost_per_kg=470.0,
        otr=250000.0,
        mvtr=1000.0,
        co2tr=700000.0,
        carbon_kgco2e_per_kg=2.4,
        water_l_per_kg=20.0,
        landfill_years=500.0,
        compost_months=None,
        recyclability=40.0,
        compostable=False,
        plastic=True,
        aliases=("ionomer", "surlyn", "ionomerpe"),
    ),
    "bio_coating": Material(
        key="bio_coating",
        name="Bio-coating (anti-fog / moisture regulator)",
        density=1.30,
        cost_per_kg=520.0,
        otr=500.0,
        mvtr=500.0,
        co2tr=1500.0,
        carbon_kgco2e_per_kg=0.5,
        water_l_per_kg=30.0,
        landfill_years=1.0,
        compost_months=4.0,
        recyclability=60.0,
        compostable=True,
        plastic=False,
        aliases=("biocoating", "antifog", "moistureregulator", "biocoat"),
    ),
}

#: Used when a name cannot be resolved at all.
DEFAULT_MATERIAL = "ldpe"


def _normalize(text: str) -> str:
    return "".join(ch for ch in text.lower() if ch.isalnum())


# Longest-alias-first so "metallizedpet" wins over "pet", "aluminum" over "alu".
_ALIAS_INDEX: list[tuple[str, str]] = sorted(
    (
        (_normalize(alias), key)
        for key, mat in MATERIALS.items()
        for alias in mat.aliases
    ),
    key=lambda pair: len(pair[0]),
    reverse=True,
)
_VALID_KEYS = set(MATERIALS)


def find_material(name: str | None) -> Material:
    """Resolve a free-text layer name ("Metallized PET (12 um)") to a material.

    Falls back to :data:`DEFAULT_MATERIAL` rather than raising so one odd layer
    name never 500s a whole simulation.
    """
    if not name:
        return MATERIALS[DEFAULT_MATERIAL]
    if name in _VALID_KEYS:
        return MATERIALS[name]
    normalized = _normalize(name)
    for alias, key in _ALIAS_INDEX:
        if alias and alias in normalized:
            return MATERIALS[key]
    return MATERIALS[DEFAULT_MATERIAL]


def resolve_material(name: str | None) -> tuple[Material, bool]:
    """Like :func:`find_material` but also reports whether it was a real match."""
    if name and (name in _VALID_KEYS or _match_key(name) is not None):
        return find_material(name), True
    return find_material(name), False


def _match_key(name: str) -> str | None:
    normalized = _normalize(name)
    for alias, key in _ALIAS_INDEX:
        if alias and alias in normalized:
            return key
    return None


def get_material(key: str) -> Material:
    return MATERIALS.get(key, MATERIALS[DEFAULT_MATERIAL])


def all_materials() -> Iterable[Material]:
    return MATERIALS.values()
