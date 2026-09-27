"""Product specification endpoints.

``POST /products`` is the entry point of the whole app: every downstream screen
(auditor, recommendations, digital twin, LCA, reports) is keyed by the returned
``productId``.
"""

from __future__ import annotations

from fastapi import APIRouter, HTTPException, Query

from models.schemas import Product, ProductCreate
from services.categories import normalize_category
from services.common import new_id, now_iso
from services.projects import on_product_created
from services.store import get_store

router = APIRouter(prefix="/products", tags=["products"])


@router.post("", response_model=Product)
def create_product(payload: ProductCreate) -> dict:
    # Pydantic already enforces maxTempC > minTempC, 0.10 <= aw <= 0.99 and
    # targetShelfLifeDays > 0 (same rules Flutter validates client-side).
    store = get_store()
    product_id = new_id("prod")
    document = {
        **payload.model_dump(),
        "category": normalize_category(payload.category),
        "categoryLabel": payload.category,
        "id": product_id,
        "createdAt": now_iso(),
    }
    store.put("products", product_id, document)
    on_product_created(store, document)
    return document


@router.get("", response_model=list[Product])
def list_products(
    userId: str = Query("demo-user"),
    limit: int = Query(50, ge=1, le=200),
) -> list[dict]:
    return get_store().list(
        "products", filters={"userId": userId}, order_by="createdAt", limit=limit
    )


@router.get("/{product_id}", response_model=Product)
def get_product(product_id: str) -> dict:
    product = get_store().get("products", product_id)
    if not product:
        raise HTTPException(status_code=404, detail="product not found")
    return product
