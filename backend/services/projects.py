"""Denormalized ``project_summary`` maintenance.

Written whenever a product / simulation / recommendation / audit is created, so
the dashboard and history screens never join across four collections live.
Keyed by ``productId``.
"""

from __future__ import annotations

from services import lca as lca_service
from services.common import now_iso
from services.fallback import PACKAGE_AREA_M2, recommendations_for
from services.store import DocumentStore

COLLECTION = "project_summary"

#: Conventional (non-optimised) stacks used as the carbon baseline per category,
#: so "carbon reduction %" is measured against a real reference structure.
CATEGORY_BASELINE_STACK: dict[str, list[dict]] = {
    "snacks": [
        {"material": "pet", "thicknessUm": 12},
        {"material": "met_pet", "thicknessUm": 12},
        {"material": "ldpe", "thicknessUm": 75},
    ],
    "dairy": [
        {"material": "paperboard", "thicknessUm": 220},
        {"material": "alu_foil", "thicknessUm": 6},
        {"material": "ldpe", "thicknessUm": 45},
    ],
    "fruitsVegetables": [{"material": "ldpe", "thicknessUm": 30}],
    "meatSeafood": [
        {"material": "evoh", "thicknessUm": 15},
        {"material": "ionomer", "thicknessUm": 95},
    ],
    "bakery": [
        {"material": "bopp", "thicknessUm": 20},
        {"material": "ldpe", "thicknessUm": 40},
    ],
    "beverages": [{"material": "pet", "thicknessUm": 25}],
    "readyToEat": [
        {"material": "pp", "thicknessUm": 30},
        {"material": "ldpe", "thicknessUm": 50},
    ],
    "grainsPulses": [
        {"material": "pp", "thicknessUm": 25},
        {"material": "pp", "thicknessUm": 25},
    ],
    "others": [
        {"material": "pet", "thicknessUm": 12},
        {"material": "ldpe", "thicknessUm": 60},
    ],
}


def _baseline_carbon_per_1k(category: str | None) -> float:
    stack = CATEGORY_BASELINE_STACK.get(category or "others", CATEGORY_BASELINE_STACK["others"])
    carbon = lca_service.carbon_footprint(stack, area_m2=PACKAGE_AREA_M2, units=1000)
    return carbon["carbonFootprintKgCO2e"]


def _eco_carbon_per_1k(category: str | None) -> tuple[float, float]:
    """Returns ``(eco_carbon_per_1k, reduction_percent)`` for the category."""
    recs = recommendations_for()
    eco = recs["sustainability_first"]["carbon_kgco2e_per_kg"]
    total_mass = sum(
        layer["thicknessUm"] * 1e-3 * 1.0 for layer in recs["sustainability_first"]["layers"]
    )
    eco_carbon = eco * total_mass * 1000
    baseline = _baseline_carbon_per_1k(category)
    reduction = ((baseline - eco_carbon) / baseline * 100.0) if baseline > 0 else 0.0
    return eco_carbon, max(0.0, min(100.0, reduction))


def _record(store: DocumentStore, product_id: str, product: dict | None = None) -> dict:
    existing = store.get(COLLECTION, product_id)
    if existing:
        return existing
    created = {
        "productId": product_id,
        "productName": (product or {}).get("name", "Untitled project"),
        "category": (product or {}).get("category", "others"),
        "userId": (product or {}).get("userId", "demo-user"),
        "shelfLifeGainedDays": 0.0,
        "ecoScore": 0.0,
        "costPer1k": 0.0,
        "carbonReductionPercent": 0.0,
        "status": "Draft",
        "simulationCount": 0,
        "createdAt": now_iso(),
        "updatedAt": now_iso(),
    }
    store.put(COLLECTION, product_id, created)
    return created


def on_product_created(store: DocumentStore, product: dict) -> dict:
    record = _record(store, product["id"], product)
    patch = {
        "productName": product.get("name"),
        "category": product.get("category"),
        "userId": product.get("userId", "demo-user"),
        "updatedAt": now_iso(),
    }
    store.update(COLLECTION, product["id"], patch)
    record.update(patch)
    return record


def on_simulation_created(store: DocumentStore, product: dict, simulation: dict) -> dict:
    record = _record(store, product["id"], product)
    target = float(product.get("targetShelfLifeDays") or 0)
    predicted = float(simulation.get("predictedShelfLifeDays") or 0)
    gained = predicted - target if predicted else 0.0
    patch = {
        "latestSimId": simulation["id"],
        "status": simulation.get("status", "Warning"),
        "shelfLifeGainedDays": round(gained, 1),
        "lastQuality": simulation.get("finalQuality"),
        "simulationCount": int(record.get("simulationCount", 0)) + 1,
        "updatedAt": now_iso(),
    }
    store.update(COLLECTION, product["id"], patch)
    record.update(patch)
    return record


def on_recommendation_created(store: DocumentStore, product: dict, recommendation: dict) -> dict:
    record = _record(store, product["id"], product)
    stack = recommendation.get("sustainability_first", {}).get("layers") or []
    recyclability = lca_service.recyclability_score(stack) if stack else {"score": 0.0}
    _, reduction = _eco_carbon_per_1k(product.get("category"))
    patch = {
        "latestRecId": recommendation["id"],
        "costPer1k": recommendation.get("cost_optimized", {}).get("cost_per_1k", 0.0),
        "ecoScore": recyclability["score"],
        "carbonReductionPercent": round(reduction, 1),
        "updatedAt": now_iso(),
    }
    store.update(COLLECTION, product["id"], patch)
    record.update(patch)
    return record


def on_audit_created(store: DocumentStore, product_id: str | None, audit: dict) -> None:
    if not product_id:
        return
    record = _record(store, product_id)
    patch = {
        "latestAuditId": audit["id"],
        "defectCount": len(audit.get("defects", [])),
        "updatedAt": now_iso(),
    }
    store.update(COLLECTION, product_id, patch)
    record.update(patch)


def get_summary(store: DocumentStore, product_id: str) -> dict | None:
    return store.get(COLLECTION, product_id)
