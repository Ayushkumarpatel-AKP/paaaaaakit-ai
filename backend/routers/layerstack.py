"""3D Layer Stack Customizer backend.

Pure math over the shared ``material_db`` — kept server-side so it can never
drift from the Digital Twin and LCA screens.
"""

from __future__ import annotations

from fastapi import APIRouter

from models.schemas import LayerStackRequest, LayerStackResponse
from services import lca as lca_service
from services.common import new_id, now_iso
from services.permeability import series_transmission
from services.store import get_store

router = APIRouter(prefix="/layerstack", tags=["layerstack"])


@router.post("/recalculate", response_model=LayerStackResponse)
def recalculate(payload: LayerStackRequest) -> dict:
    layers = [layer.model_dump() for layer in payload.layers]
    permeability = series_transmission(layers)
    cost = lca_service.cost_breakdown(
        layers, area_m2=payload.areaM2, units=payload.units
    )
    recyclability = lca_service.recyclability_score(layers, payload.areaM2)

    stack_id = new_id("stack")
    document = {
        "id": stack_id,
        "productId": payload.productId,
        "layers": layers,
        "totalThickness": round(permeability.total_thickness_um, 2),
        "seriesOTR": round(permeability.otr, 4),
        "seriesMVTR": round(permeability.mvtr, 4),
        "seriesCO2TR": round(permeability.co2tr, 4),
        "stackWeight": round(permeability.mass_per_m2 * payload.areaM2 * payload.units, 6),
        "stackWeightPerM2": round(permeability.mass_per_m2, 6),
        "estimatedCost": cost["per_1k_units"]["total"],
        "recyclabilityScore": recyclability["score"],
        "createdAt": now_iso(),
    }
    get_store().put("layerStacks", stack_id, document)

    return {
        "stackId": stack_id,
        "layers": [
            {
                "material": layer.material.key,
                "name": layer.material.name,
                "thicknessUm": layer.thickness_um,
                "density": layer.material.density,
            }
            for layer in permeability.layers
        ],
        "totalThickness": document["totalThickness"],
        "seriesOTR": document["seriesOTR"],
        "seriesMVTR": document["seriesMVTR"],
        "seriesCO2TR": document["seriesCO2TR"],
        "stackWeight": document["stackWeight"],
        "stackWeightPerM2": document["stackWeightPerM2"],
        "estimatedCost": document["estimatedCost"],
        "recyclabilityScore": document["recyclabilityScore"],
    }
