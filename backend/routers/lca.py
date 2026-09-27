"""Cost & Sustainability LCA endpoint."""

from __future__ import annotations

from fastapi import APIRouter

from models.schemas import LcaRequest
from services import lca as lca_service
from services.material_db import all_materials
from services.common import new_id, now_iso
from services.store import get_store

router = APIRouter(prefix="/lca", tags=["lca"])


@router.post("/calculate")
def calculate(payload: LcaRequest) -> dict:
    layers = [layer.model_dump() for layer in payload.layers]
    units = payload.productionVolume
    area = payload.areaM2

    cost = lca_service.cost_breakdown(
        layers,
        area_m2=area,
        units=units,
        distance_km=payload.transportDistanceKm,
        freight_mode=payload.freightMode,
        jurisdiction=payload.jurisdiction,
    )
    carbon = lca_service.carbon_footprint(
        layers,
        area_m2=area,
        units=units,
        distance_km=payload.transportDistanceKm,
        freight_mode=payload.freightMode,
    )
    water = lca_service.water_usage(layers, area_m2=area, units=units)
    recyclability = lca_service.recyclability_score(layers, area)
    degradation = lca_service.degradation_timeline(layers, area)
    epr = lca_service.epr_tax_comparison(
        layers, area_m2=area, units=units, jurisdiction=payload.jurisdiction
    )

    lca_id = new_id("lca")
    document = {
        "id": lca_id,
        "productId": payload.productId,
        "layers": layers,
        "currency": lca_service.CURRENCY,
        "costPerUnit": cost["per_unit"]["total"],
        "costPer1kUnits": cost["per_1k_units"]["total"],
        "costBreakdown": cost,
        "carbonFootprintKgCO2e": carbon["carbonFootprintKgCO2e"],
        "carbonBreakdown": carbon,
        "waterUsageL": water["waterUsageL"],
        "waterBreakdown": water,
        "recyclabilityScore": recyclability["score"],
        "degradationYears": degradation["landfill_years"],
        "degradation": degradation,
        "eprTaxComparison": epr,
        "productionVolume": units,
        "createdAt": now_iso(),
    }
    get_store().put("lcaReports", lca_id, document)
    return document


@router.get("/jurisdictions")
def jurisdictions() -> dict:
    return {
        "currency": lca_service.CURRENCY,
        "defaultJurisdiction": lca_service.DEFAULT_JURISDICTION,
        "ratesPerKg": lca_service.EPR_TAX_PER_KG,
        "note": (
            "Illustrative EPR plastic-fee rates in INR — rules and rates vary by "
            "jurisdiction."
        ),
    }


@router.get("/materials")
def materials() -> list[dict]:
    """Reference table used by the cost/sustainability screen legends."""
    return [
        {
            "key": material.key,
            "name": material.name,
            "density": material.density,
            "costPerKgInr": material.cost_per_kg,
            "carbonKgCO2ePerKg": material.carbon_kgco2e_per_kg,
            "waterLPerKg": material.water_l_per_kg,
            "recyclability": material.recyclability,
            "compostable": material.compostable,
            "landfillYears": material.landfill_years,
        }
        for material in all_materials()
    ]
