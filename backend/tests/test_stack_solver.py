"""Tests for the product-specific stack solver.

Two things matter here:
1. different products must get different stacks (that is the whole point), and
2. the solver must agree with the digital-twin / shelf-life engine, otherwise the
   recommendation screen and the simulator would contradict each other.
"""

from __future__ import annotations

from services.digital_twin import build_shelf_life
from services.shelf_life import category_spec
from services.stack_solver import TIERS, _candidates, solve_recommendations


def _product(
    *,
    name="Potato Chips",
    category="snacks",
    water_activity=0.30,
    fat=35.0,
    shelf_life_days=180,
    min_temp=15.0,
    max_temp=30.0,
    humidity=60.0,
    budget=3000.0,
    moisture=3.0,
) -> dict:
    return {
        "name": name,
        "category": category,
        "waterActivity": water_activity,
        "fatContent": fat,
        "targetShelfLifeDays": shelf_life_days,
        "minTempC": min_temp,
        "maxTempC": max_temp,
        "relativeHumidityPct": humidity,
        "budgetPer1kUnits": budget,
        "moisturePct": moisture,
    }


CHIPS = _product()
MILK = _product(
    name="Pasteurized Milk",
    category="dairy",
    water_activity=0.97,
    fat=3.5,
    shelf_life_days=14,
    min_temp=2.0,
    max_temp=8.0,
    humidity=70.0,
    budget=5000.0,
    moisture=88.0,
)
BEEF = _product(
    name="Prime Beef",
    category="meatSeafood",
    water_activity=0.98,
    fat=20.0,
    shelf_life_days=10,
    min_temp=-2.0,
    max_temp=4.0,
    humidity=85.0,
    budget=5000.0,
    moisture=70.0,
)


def test_solver_returns_every_tier_with_the_expected_contract():
    """The Flutter client parses these keys; they must survive the solver."""
    tiers = solve_recommendations(CHIPS)

    assert set(tiers) == set(TIERS)
    for tier in TIERS:
        payload = tiers[tier]
        assert payload["structure"]
        assert payload["layers"]
        assert payload["otr_cc_m2_day"] > 0
        assert payload["mvtr_g_m2_day"] > 0
        assert payload["cost_per_1k"] > 0
        assert payload["totalThicknessUm"] > 0
        assert payload["tier"] == tier
        # Solver-derived, honest fields.
        assert isinstance(payload["meets_target"], bool)
        assert payload["predicted_shelf_life_days"] > 0
        assert payload["limiting_factor"] in {
            "quality",
            "moisture",
            "oxidation",
            "microbial",
            "none",
        }
        assert payload["target_shelf_life_days"] == 180.0
        assert payload["why"]


def test_stacks_differ_between_products():
    """The old engine returned identical templates for every product.

    Note ``max_barrier`` is allowed to converge: "the best barrier available"
    can legitimately be the same stack for two different products. The tiers
    that must respond to the product are the cost and sustainability ones.
    """
    chips = solve_recommendations(CHIPS)
    milk = solve_recommendations(MILK)

    # A 180-day / 35%-fat snack needs a barrier core; a 14-day chilled dairy
    # product does not, so the cheap stack is a different shape entirely.
    assert len(chips["cost_optimized"]["layers"]) != len(
        milk["cost_optimized"]["layers"]
    )
    assert (
        chips["cost_optimized"]["structure"] != milk["cost_optimized"]["structure"]
    )

    # And the numbers a user reads really do differ.
    assert chips["cost_optimized"]["cost_per_1k"] != milk["cost_optimized"]["cost_per_1k"]
    assert (
        chips["cost_optimized"]["limiting_factor"]
        != milk["cost_optimized"]["limiting_factor"]
        or chips["cost_optimized"]["mvtr_g_m2_day"]
        != milk["cost_optimized"]["mvtr_g_m2_day"]
    )


def test_a_long_life_fatty_snack_requires_an_oxygen_barrier():
    """Physics, not a template, should force a real barrier core here."""
    tiers = solve_recommendations(CHIPS)
    for tier in TIERS:
        materials = [layer["material"] for layer in tiers[tier]["layers"]]
        # Every plausible stack for a 35% fat / 180-day product needs a barrier.
        assert any(
            material in {"met_pet", "alox_pet", "evoh", "alu_foil", "nanocellulose"}
            for material in materials
        ), f"{tier} has no barrier core: {materials}"


def test_max_barrier_beats_the_other_tiers_on_barrier():
    tiers = solve_recommendations(CHIPS)
    best = tiers["max_barrier"]
    for tier in ("cost_optimized", "sustainability_first"):
        other = tiers[tier]
        assert best["otr_cc_m2_day"] <= other["otr_cc_m2_day"]
        assert best["mvtr_g_m2_day"] <= other["mvtr_g_m2_day"]


def test_cost_optimized_is_the_cheapest_feasible_option():
    tiers = solve_recommendations(CHIPS)
    costs = {tier: tiers[tier]["cost_per_1k"] for tier in TIERS}
    assert costs["cost_optimized"] == min(costs.values())


def test_solver_agrees_with_the_shelf_life_engine():
    """Guards against the solver drifting away from the simulator's physics."""
    tiers = solve_recommendations(CHIPS)
    payload = tiers["cost_optimized"]

    class _Request:
        """Minimal stand-in for SimulationRequest."""

        layers = payload["layers"]
        durationDays = payload["target_shelf_life_days"] * 1.25
        temperatureC = 22.5  # (minTemp 15 + maxTemp 30) / 2
        humidityRH = 60.0
        gasMix = None
        barrierThicknessUm = None
        qualityThreshold = None

    engine = build_shelf_life(CHIPS, _Request(), n_points=41)
    engine_days = engine["shelfLife"].predicted_shelf_life_days

    # Same stack, same conditions -> the same answer, within integration noise.
    assert abs(engine_days - payload["predicted_shelf_life_days"]) < 3.0
    assert engine["shelfLife"].limiting_factor == payload["limiting_factor"]


def test_budget_is_respected_when_anything_is_affordable():
    generous = solve_recommendations(_product(budget=5000.0))
    assert generous["cost_optimized"]["within_budget"] is True

    # An impossibly low budget must not silently claim to fit.
    tight = solve_recommendations(_product(budget=1.0))
    assert tight["cost_optimized"]["within_budget"] is False


def test_short_life_product_still_returns_three_tiers():
    tiers = solve_recommendations(MILK)
    assert len(tiers) == 3
    for tier in TIERS:
        assert tiers[tier]["predicted_shelf_life_days"] >= 14.0


def test_candidate_space_is_bounded_and_well_formed():
    """The search runs per request, so keep it small and sane."""
    candidates = _candidates()
    assert 200 < len(candidates) < 4000
    for candidate in candidates:
        materials = [material for material, _ in candidate.layers]
        # No material twice in one laminate, and every stack is 2 or 3 layers.
        assert len(set(materials)) == len(materials)
        assert len(candidate.layers) in (2, 3)
        assert all(thickness > 0 for _, thickness in candidate.layers)


def test_unknown_category_falls_back_instead_of_crashing():
    tiers = solve_recommendations(_product(category="not-a-real-category"))
    assert set(tiers) == set(TIERS)
    assert all(tiers[tier]["structure"] for tier in TIERS)
