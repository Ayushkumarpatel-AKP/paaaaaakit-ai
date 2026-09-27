"""Project history & reports listing.

Reads only the denormalized ``project_summary`` collection, so this screen never
joins across products/simulations/audits/recommendations live.
"""

from __future__ import annotations

from fastapi import APIRouter, Query

from services.categories import normalize_category
from services.common import parse_iso
from services.store import get_store

router = APIRouter(prefix="/history", tags=["history"])


@router.get("")
def history(
    userId: str = Query("demo-user"),
    search: str | None = Query(None),
    category: str | None = Query(None),
    dateFrom: str | None = Query(None),
    dateTo: str | None = Query(None),
    limit: int = Query(50, ge=1, le=200),
) -> dict:
    store = get_store()
    projects = store.list("project_summary", filters={"userId": userId}, limit=500)

    needle = (search or "").strip().lower()
    category_key = normalize_category(category) if category else None
    start = parse_iso(dateFrom)
    end = parse_iso(dateTo)

    filtered: list[dict] = []
    for project in projects:
        if needle and needle not in str(project.get("productName", "")).lower():
            continue
        if category_key and normalize_category(project.get("category")) != category_key:
            continue
        created = parse_iso(project.get("createdAt"))
        if start and created and created < start:
            continue
        if end and created and created > end:
            continue
        filtered.append(project)

    filtered.sort(key=lambda p: p.get("updatedAt") or p.get("createdAt") or "", reverse=True)
    return {
        "count": len(filtered),
        "projects": filtered[:limit],
        "facets": {
            "categories": sorted({normalize_category(p.get("category")) for p in projects}),
            "statuses": sorted({p.get("status", "Draft") for p in projects}),
        },
    }
