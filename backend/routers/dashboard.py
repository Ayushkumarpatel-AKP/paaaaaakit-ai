"""Home dashboard aggregation over ``project_summary`` + ``simulations``."""

from __future__ import annotations

from fastapi import APIRouter, Query

from services.store import get_store

router = APIRouter(prefix="/dashboard", tags=["dashboard"])


@router.get("/summary")
def summary(userId: str = Query("demo-user")) -> dict:
    store = get_store()
    projects = store.list("project_summary", filters={"userId": userId}, limit=500)

    if projects:
        avg_shelf = sum(float(p.get("shelfLifeGainedDays") or 0) for p in projects) / len(projects)
        avg_carbon = sum(float(p.get("carbonReductionPercent") or 0) for p in projects) / len(projects)
        avg_eco = sum(float(p.get("ecoScore") or 0) for p in projects) / len(projects)
    else:
        avg_shelf = avg_carbon = avg_eco = 0.0

    return {
        "carbonReductionPercent": round(avg_carbon, 1),
        "avgShelfLifeExtensionDays": round(avg_shelf, 1),
        "activeProjectCount": len(projects),
        "avgEcoScore": round(avg_eco, 1),
        "baselineNote": (
            "Reduction is measured against a conventional stack per category "
            "(industry-average carbon factors)."
        ),
    }


@router.get("/recent-feed")
def recent_feed(
    userId: str = Query("demo-user"),
    limit: int = Query(10, ge=1, le=50),
) -> list[dict]:
    store = get_store()
    simulations = store.list(
        "simulations",
        filters={"userId": userId},
        order_by="createdAt",
        limit=limit,
    )

    feed: list[dict] = []
    for simulation in simulations:
        product = store.get("products", simulation.get("productId", "")) or {}
        feed.append(
            {
                "id": simulation.get("id"),
                "simId": simulation.get("id"),
                "productId": simulation.get("productId"),
                "productName": product.get("name", "Untitled"),
                "category": product.get("category", "others"),
                "chamberPreset": simulation.get("chamberPreset"),
                "status": simulation.get("status"),
                "finalQuality": simulation.get("finalQuality"),
                "predictedShelfLifeDays": simulation.get("predictedShelfLifeDays"),
                "createdAt": simulation.get("createdAt"),
            }
        )
    return feed
