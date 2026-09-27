"""Unit tests for the real-physics services (no LLM, no network)."""

from __future__ import annotations

import math

import pytest

from services import arrhenius, lca, shelf_life
from services.digital_twin import run_simulation
from services.material_db import find_material
from services.permeability import series_transmission
from models.schemas import SimulationRequest


# ---------------------------------------------------------------------------
# Arrhenius
# ---------------------------------------------------------------------------
def test_arrhenius_increases_with_temperature():
    k_cold = arrhenius.arrhenius_k(A=1e6, ea_kj_mol=60.0, temperature_c=4.0)
    k_warm = arrhenius.arrhenius_k(A=1e6, ea_kj_mol=60.0, temperature_c=38.0)
    assert k_warm > k_cold


def test_calibration_hits_target_shelf_life():
    k, _ = arrhenius.build_rate_constant("snacks", 25.0, 180)
    crossing = arrhenius.time_to_threshold(k, threshold=70.0)
    assert crossing == pytest.approx(180.0, rel=1e-6)


def test_quality_curve_is_monotonic_and_spans_duration():
    times, quality = arrhenius.integrate_quality(k=0.002, duration_days=200, n_points=41)
    assert len(times) == len(quality) == 41
    assert times[0] == 0.0 and times[-1] == pytest.approx(200.0)
    assert quality[0] == pytest.approx(100.0)
    assert all(b <= a for a, b in zip(quality, quality[1:]))


# ---------------------------------------------------------------------------
# Permeability
# ---------------------------------------------------------------------------
def test_series_permeability_matches_resistance_sum():
    layers = [
        {"material": "pet", "thicknessUm": 12},
        {"material": "ldpe", "thicknessUm": 60},
    ]
    stack = series_transmission(layers)
    expected_inv = 12 / find_material("pet").otr + 60 / find_material("ldpe").otr
    assert stack.otr == pytest.approx(1 / expected_inv)
    assert stack.total_thickness_um == pytest.approx(72.0)


def test_adding_barrier_layer_reduces_transmission():
    base = series_transmission([{"material": "ldpe", "thicknessUm": 80}])
    with_barrier = series_transmission(
        [
            {"material": "ldpe", "thicknessUm": 80},
            {"material": "evoh", "thicknessUm": 15},
        ]
    )
    assert with_barrier.otr < base.otr


def test_unknown_material_falls_back_without_raising():
    stack = series_transmission([{"material": "unobtainium", "thicknessUm": 20}])
    assert stack.otr > 0


def test_mass_per_m2_is_physical():
    stack = series_transmission([{"material": "pet", "thicknessUm": 12}])
    # 12 um PET at 1.38 g/cm^3 -> ~0.01656 kg/m^2
    assert stack.mass_per_m2 == pytest.approx(0.01656, rel=1e-3)


# ---------------------------------------------------------------------------
# Shelf life
# ---------------------------------------------------------------------------
def test_moisture_gain_scales_with_mvtr():
    low = shelf_life.moisture_gain_curve(2.0, 85.0, 20.0, 100, n_points=11)
    high = shelf_life.moisture_gain_curve(10.0, 85.0, 20.0, 100, n_points=11)
    assert high[-1] > low[-1]
    assert low[0] == 0.0


def test_microbial_growth_logistic_is_bounded():
    spec = shelf_life.category_spec("dairy")
    times = [i * 5.0 for i in range(21)]
    curve = shelf_life.microbial_curve(spec, 0.99, 30.0, times)
    assert curve[0] == pytest.approx(spec.initial_log_cfu)
    assert all(b >= a for a, b in zip(curve, curve[1:]))
    assert curve[-1] <= 9.0


def test_first_crossing_interpolates():
    times = [0.0, 10.0, 20.0]
    values = [0.0, 5.0, 15.0]
    assert shelf_life.first_crossing(times, values, 10.0) == pytest.approx(15.0)
    assert shelf_life.first_crossing(times, values, 999.0) is None


def test_predict_shelf_life_picks_earliest_failure():
    times = [0.0, 10.0, 20.0, 30.0]
    result = shelf_life.predict_shelf_life(
        category="snacks",
        time_days=times,
        quality=[100, 90, 80, 60],
        moisture_gain=[0, 1, 2, 4],
        oxygen_ppm=[0, 10, 20, 30],
        fat_content_pct=35.0,
        water_activity=0.25,
        temperature_c=25.0,
    )
    assert result.predicted_shelf_life_days < 30
    assert result.limiting_factor in {"quality", "moisture", "oxidation", "microbial"}


# ---------------------------------------------------------------------------
# LCA
# ---------------------------------------------------------------------------
def test_cost_breakdown_components_sum():
    layers = [{"material": "pet", "thicknessUm": 12}, {"material": "ldpe", "thicknessUm": 60}]
    cost = lca.cost_breakdown(layers, area_m2=0.05, units=1000)
    per_unit = cost["per_unit"]
    assert per_unit["total"] == pytest.approx(
        per_unit["rawMaterial"] + per_unit["extrusion"] + per_unit["transport"] + per_unit["eolDisposalTax"]
    )
    assert cost["per_1k_units"]["total"] > 0


def test_lca_is_priced_for_the_indian_market_in_rupees():
    layers = [
        {"material": "pet", "thicknessUm": 12},
        {"material": "met_pet", "thicknessUm": 12},
        {"material": "ldpe", "thicknessUm": 75},
    ]
    cost = lca.cost_breakdown(layers, area_m2=0.05, units=1000)
    assert cost["currency"]["code"] == "INR"
    assert cost["currency"]["symbol"] == "\u20b9"
    assert lca.DEFAULT_JURISDICTION == "IN"

    # Realistic Indian pouch pricing: a few rupees, not fractions of a dollar.
    per_pack = cost["per_unit"]["total"]
    assert 0.4 <= per_pack <= 4.0, per_pack
    assert cost["per_1k_units"]["total"] == pytest.approx(per_pack * 1000, rel=1e-6)


def test_material_prices_are_in_inr_scale():
    # ₹/kg for converted film — not single-digit USD-equivalent numbers.
    for key in ("pet", "ldpe", "met_pet", "pla", "paperboard"):
        assert find_material(key).cost_per_kg >= 50, key


def test_mono_material_scores_better_than_multilayer():
    mono = lca.recyclability_score([{"material": "ldpe", "thicknessUm": 80}])
    mixed = lca.recyclability_score(
        [
            {"material": "pet", "thicknessUm": 12},
            {"material": "alu_foil", "thicknessUm": 7},
            {"material": "ldpe", "thicknessUm": 60},
        ]
    )
    assert mono["score"] > mixed["score"]


def test_ecos_stack_reduces_plastic_mass():
    layers = [
        {"material": "pet", "thicknessUm": 12},
        {"material": "met_pet", "thicknessUm": 12},
        {"material": "ldpe", "thicknessUm": 60},
    ]
    comparison = lca.epr_tax_comparison(layers, area_m2=0.05, units=1000, jurisdiction="EU")
    assert comparison["ecoStack"]["plasticMassKg"] < comparison["current"]["plasticMassKg"]
    assert comparison["savingPer1kUnits"] > 0


def test_transport_adds_cost_and_carbon():
    layers = [{"material": "ldpe", "thicknessUm": 80}]
    near = lca.cost_breakdown(layers, area_m2=0.05, units=1000, distance_km=100)
    far = lca.cost_breakdown(layers, area_m2=0.05, units=1000, distance_km=9000)
    assert far["per_1k_units"]["total"] > near["per_1k_units"]["total"]


# ---------------------------------------------------------------------------
# Digital twin
# ---------------------------------------------------------------------------
def test_simulation_series_are_consistent():
    product = {
        "id": "prod_test",
        "category": "snacks",
        "targetShelfLifeDays": 180,
        "fatContent": 35.0,
        "waterActivity": 0.25,
    }
    request = SimulationRequest(
        productId="prod_test",
        chamberPreset="Tropical",
        durationDays=180,
    ).resolved()
    result = run_simulation(product, request, n_points=37)

    assert len(result["time_days"]) == len(result["quality"]) == 37
    assert len(result["moisture_gain_g_m2"]) == 37
    assert len(result["oxygen_accum_ppm"]) == 37
    assert result["status"] in {"Optimal", "Warning", "Action Needed"}
    assert 0.0 <= result["finalQuality"] <= 100.0


def test_high_barrier_stack_keeps_headspace_oxygen_lower():
    product = {
        "id": "prod_test",
        "category": "snacks",
        "targetShelfLifeDays": 180,
        "fatContent": 35.0,
        "waterActivity": 0.25,
    }
    high_barrier = [
        {"material": "pet", "thicknessUm": 12},
        {"material": "met_pet", "thicknessUm": 12},
        {"material": "ldpe", "thicknessUm": 60},
    ]
    low_barrier = [{"material": "ldpe", "thicknessUm": 60}]

    barrier = run_simulation(
        product,
        SimulationRequest(productId="p", chamberPreset="Standard", layers=high_barrier).resolved(),
    )
    permeable = run_simulation(
        product,
        SimulationRequest(productId="p", chamberPreset="Standard", layers=low_barrier).resolved(),
    )
    assert barrier["oxygen_accum_ppm"][-1] < permeable["oxygen_accum_ppm"][-1]


def test_cold_temperature_slows_moisture_uptake():
    warm = shelf_life.moisture_gain_curve(5.0, 85.0, 20.0, 100, temperature_c=38.0)
    cold = shelf_life.moisture_gain_curve(5.0, 85.0, 20.0, 100, temperature_c=4.0)
    assert cold[-1] < warm[-1]


def test_tropical_chamber_degrades_faster_than_cold_chain():
    product = {
        "id": "prod_test",
        "category": "dairy",
        "targetShelfLifeDays": 21,
        "fatContent": 3.5,
        "waterActivity": 0.99,
    }
    tropical = run_simulation(
        product, SimulationRequest(productId="p", chamberPreset="Tropical").resolved()
    )
    cold = run_simulation(
        product, SimulationRequest(productId="p", chamberPreset="Cold Chain").resolved()
    )
    assert tropical["k"] > cold["k"]
    assert tropical["finalQuality"] < cold["finalQuality"]
