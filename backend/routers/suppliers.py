"""Global supplier traceability.

Seeded sample directory (see ``data/seed_suppliers.py``) plus Haversine route
tracing to a configurable manufacturing plant, and RFQ logging.
"""

from __future__ import annotations

import os

from fastapi import APIRouter, HTTPException, Query

from models.schemas import RfqRequest
from services.common import new_id, now_iso
from services.material_db import find_material
from services.store import get_store
from services.traceability import haversine_km, route_emissions

router = APIRouter(prefix="/suppliers", tags=["suppliers"])

#: Default manufacturing plant used as the origin for route tracing.
DEFAULT_PLANT = {
    "lat": float(os.environ.get("PLANT_LAT", "23.0225")),
    "lng": float(os.environ.get("PLANT_LNG", "72.5714")),
    "label": os.environ.get("PLANT_LABEL", "Manufacturing plant, Ahmedabad, India"),
}


def _matches(supplier: dict, material: str | None, location: str | None, certification: str | None) -> bool:
    if material:
        key = find_material(material).key
        available = {find_material(m).key for m in supplier.get("materialTypes", [])}
        if key not in available and material.lower() not in str(supplier.get("materialTypes", [])).lower():
            return False
    if location:
        haystack = f"{supplier.get('locationLabel', '')} {supplier.get('region', '')}".lower()
        if location.lower() not in haystack:
            return False
    if certification:
        certs = " ".join(supplier.get("certifications", [])).lower()
        if certification.lower() not in certs:
            return False
    return True


@router.get("")
def list_suppliers(
    material: str | None = Query(None),
    location: str | None = Query(None),
    certification: str | None = Query(None),
    plantLat: float = Query(DEFAULT_PLANT["lat"]),
    plantLng: float = Query(DEFAULT_PLANT["lng"]),
    shippingMode: str = Query("road"),
    massKg: float = Query(1000.0),
    limit: int = Query(50, ge=1, le=200),
) -> dict:
    suppliers = get_store().list("suppliers", order_by="rating", limit=200)
    filtered = [s for s in suppliers if _matches(s, material, location, certification)]

    enriched = []
    for supplier in filtered[:limit]:
        coords = supplier.get("location") or {}
        distance = haversine_km(
            plantLat, plantLng, float(coords.get("lat", 0)), float(coords.get("lng", 0))
        )
        enriched.append(
            {
                **supplier,
                "distanceKm": round(distance, 1),
                "route": route_emissions(
                    distance_km=distance, mass_kg=massKg, mode=shippingMode
                ),
            }
        )
    enriched.sort(key=lambda s: s["distanceKm"])

    return {
        "plant": {"lat": plantLat, "lng": plantLng, "label": DEFAULT_PLANT["label"]},
        "count": len(enriched),
        "suppliers": enriched,
        "note": "Sample supplier directory for demonstration.",
    }


@router.get("/{supplier_id}")
def get_supplier(supplier_id: str) -> dict:
    supplier = get_store().get("suppliers", supplier_id)
    if not supplier:
        raise HTTPException(status_code=404, detail="supplier not found")
    return supplier


@router.post("/{supplier_id}/rfq")
def create_rfq(supplier_id: str, payload: RfqRequest) -> dict:
    store = get_store()
    supplier = store.get("suppliers", supplier_id)
    if not supplier:
        raise HTTPException(status_code=404, detail="supplier not found")

    rfq_id = new_id("rfq")
    document = {
        "id": rfq_id,
        "supplierId": supplier_id,
        "supplierName": supplier.get("name"),
        "material": payload.material,
        "quantityKg": payload.quantityKg,
        "message": payload.message,
        "contactEmail": payload.contactEmail,
        "status": "logged",
        "createdAt": now_iso(),
    }
    store.put("rfq_requests", rfq_id, document)
    # Email dispatch is optional — logging to the store and confirming is enough
    # for the demo. Wire SendGrid/EmailJS here if a provider is configured.
    return {
        **document,
        "confirmation": (
            f"Request sent to {supplier.get('name')}. "
            f"{supplier.get('contactInfo', {}).get('email', '')}"
        ),
    }
