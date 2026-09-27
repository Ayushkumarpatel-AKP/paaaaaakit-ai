"""Arrhenius reaction kinetics + the quality-decay ODE.

Real physics, no LLM. This module is the credibility anchor of the Digital
Twin screen:

* ``k = A * exp(-Ea / (R * T))``  — the standard Arrhenius rate constant
* ``dQ/dt = -k * Q``              — first-order quality loss, integrated with
  ``scipy.integrate.solve_ivp``

Calibration note (important to disclose in the UI): the pre-exponential factor
``A`` is back-solved so that, at a 25 degC reference, quality crosses the spec
threshold exactly at the product's declared *target* shelf life. Temperature,
gas mix, moisture and water activity then move the prediction away from the
label claim — which is what makes the simulator useful.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

from scipy.integrate import solve_ivp

from services.categories import normalize_category

GAS_CONSTANT_J = 8.314  # J / (mol * K)
REFERENCE_TEMP_C = 25.0
DEFAULT_QUALITY_THRESHOLD = 70.0


@dataclass(frozen=True)
class Kinetics:
    """Activation energy + reference rate for a food category."""

    category: str
    ea_kj_mol: float
    #: fractional quality loss per day at 25 degC (recalibrated per product)
    k_ref_25: float


# Activation energies are typical literature ranges for food quality loss
# (lipid oxidation / vitamin degradation / microbial spoilage), 40-100 kJ/mol.
CATEGORY_KINETICS: dict[str, Kinetics] = {
    "snacks": Kinetics("snacks", 60.0, 0.0020),
    "dairy": Kinetics("dairy", 85.0, 0.0120),
    "fruitsVegetables": Kinetics("fruitsVegetables", 70.0, 0.0110),
    "fruits_vegetables": Kinetics("fruitsVegetables", 70.0, 0.0110),
    "meatSeafood": Kinetics("meatSeafood", 75.0, 0.0130),
    "meat_seafood": Kinetics("meatSeafood", 75.0, 0.0130),
    "bakery": Kinetics("bakery", 55.0, 0.0055),
    "beverages": Kinetics("beverages", 65.0, 0.0040),
    "readyToEat": Kinetics("readyToEat", 80.0, 0.0090),
    "ready_to_eat": Kinetics("readyToEat", 80.0, 0.0090),
    "grainsPulses": Kinetics("grainsPulses", 50.0, 0.0016),
    "grains_pulses": Kinetics("grainsPulses", 50.0, 0.0016),
    "others": Kinetics("others", 60.0, 0.0040),
}


def kinetic_params(category: str | None) -> Kinetics:
    key = normalize_category(category)
    return CATEGORY_KINETICS.get(key, CATEGORY_KINETICS["others"])


def arrhenius_k(A: float, ea_kj_mol: float, temperature_c: float) -> float:
    """Arrhenius rate constant at ``temperature_c`` (degrees Celsius)."""
    t_kelvin = temperature_c + 273.15
    ea_j = ea_kj_mol * 1000.0
    return A * math.exp(-ea_j / (GAS_CONSTANT_J * t_kelvin))


def _A_from_k_ref(k_ref: float, ea_kj_mol: float) -> float:
    """Back-solve the pre-exponential factor so k(25 degC) == k_ref."""
    t_kelvin = REFERENCE_TEMP_C + 273.15
    ea_j = ea_kj_mol * 1000.0
    return k_ref / math.exp(-ea_j / (GAS_CONSTANT_J * t_kelvin))


def calibrate_k_ref(
    target_shelf_life_days: float,
    threshold: float = DEFAULT_QUALITY_THRESHOLD,
    q0: float = 100.0,
    safety_factor: float = 1.0,
) -> float:
    """Rate constant at 25 degC that hits ``threshold`` at the target shelf life."""
    if target_shelf_life_days <= 0:
        return CATEGORY_KINETICS["others"].k_ref_25
    days = max(target_shelf_life_days * safety_factor, 1.0)
    return math.log(q0 / threshold) / days


def build_rate_constant(
    category: str | None,
    temperature_c: float,
    target_shelf_life_days: float,
    threshold: float = DEFAULT_QUALITY_THRESHOLD,
) -> tuple[float, Kinetics]:
    """Return ``(k, kinetics)`` for the given temperature and label claim."""
    kin = kinetic_params(category)
    k_ref = calibrate_k_ref(target_shelf_life_days, threshold)
    A = _A_from_k_ref(k_ref, kin.ea_kj_mol)
    return arrhenius_k(A, kin.ea_kj_mol, temperature_c), kin


def quality_ode(_t: float, q: list[float], k: float) -> list[float]:
    """dQ/dt = -k * Q (first-order quality decay)."""
    return [-k * q[0]]


def integrate_quality(
    k: float,
    duration_days: float,
    n_points: int = 61,
    q0: float = 100.0,
) -> tuple[list[float], list[float]]:
    """Integrate the quality ODE with ``solve_ivp`` and sample it evenly.

    Returns ``(time_days, quality)`` lists ready to drop into
    ``simulation_chart.dart``.
    """
    duration = max(float(duration_days), 0.0)
    if duration == 0:
        return [0.0], [q0]
    sol = solve_ivp(
        quality_ode,
        (0.0, duration),
        [q0],
        args=(k,),
        dense_output=True,
        method="RK45",
        rtol=1e-6,
        atol=1e-9,
    )
    times = [duration * i / (n_points - 1) for i in range(n_points)]
    qualities = [float(sol.sol(t)[0]) for t in times]
    return times, qualities


def time_to_threshold(
    k: float,
    threshold: float = DEFAULT_QUALITY_THRESHOLD,
    q0: float = 100.0,
) -> float | None:
    """Analytic first-crossing time of ``threshold`` for dQ/dt = -k*Q."""
    if k <= 0 or threshold >= q0 or threshold <= 0:
        return None
    return math.log(q0 / threshold) / k
