"""Digital Twin + Shelf Life endpoints.

Chamber presets are just default parameter payloads — they all funnel into the
same physics engine, so there is no special-case backend branch.
"""

from __future__ import annotations

from fastapi import APIRouter, HTTPException

from models.schemas import ShelfLifeRequest, ShelfLifeResponse, SimulationRequest
from services.common import new_id, now_iso
from services.digital_twin import ASSUMPTIONS, build_shelf_life, run_simulation
from services.projects import on_simulation_created
from services.store import get_store

router = APIRouter(prefix="/simulate", tags=["simulate"])


def _save_simulation(product: dict, request: SimulationRequest, result: dict, predicted: float) -> str:
    store = get_store()
    sim_id = new_id("sim")
    document = {
        "id": sim_id,
        "productId": product["id"],
        "userId": product.get("userId", "demo-user"),
        "chamberPreset": request.chamberPreset or "Standard",
        "temperatureC": result["temperatureC"],
        "humidityRH": result["humidityRH"],
        "gasMix": result["gasMix"],
        "barrierThicknessUm": round(result["barrierThicknessUm"], 2),
        "layers": result["layers"],
        "status": result["status"],
        "finalQuality": result["finalQuality"],
        "predictedShelfLifeDays": predicted,
        "otr": round(result["permeability"].otr, 3),
        "mvtr": round(result["permeability"].mvtr, 3),
        "durationDays": result["durationDays"],
        "resultTimeSeries": {
            "time": result["time_days"],
            "quality": result["quality"],
            "moistureGain": result["moisture_gain_g_m2"],
            "oxygenAccum": result["oxygen_accum_ppm"],
        },
        "createdAt": now_iso(),
    }
    store.put("simulations", sim_id, document)
    on_simulation_created(store, product, document)
    return sim_id


@router.post("/digital-twin")
def digital_twin(payload: SimulationRequest) -> dict:
    store = get_store()
    product = store.get("products", payload.productId)
    if not product:
        raise HTTPException(status_code=404, detail="product not found")

    request = payload.resolved()
    bundle = build_shelf_life(product, request)
    result = bundle["sim"]
    predicted = bundle["shelfLife"].predicted_shelf_life_days
    sim_id = _save_simulation(product, request, result, predicted)

    return {
        "simId": sim_id,
        "productId": product["id"],
        "chamberPreset": request.chamberPreset or "Standard",
        "temperatureC": result["temperatureC"],
        "humidityRH": result["humidityRH"],
        "gasMix": result["gasMix"],
        "barrierThicknessUm": round(result["barrierThicknessUm"], 2),
        "durationDays": result["durationDays"],
        "status": result["status"],
        "finalQuality": result["finalQuality"],
        "otr": round(result["permeability"].otr, 3),
        "mvtr": round(result["permeability"].mvtr, 3),
        "predictedShelfLifeDays": predicted,
        "resultTimeSeries": {
            "time": [round(t, 3) for t in result["time_days"]],
            "quality": [round(q, 3) for q in result["quality"]],
            "moistureGain": [round(m, 5) for m in result["moisture_gain_g_m2"]],
            "oxygenAccum": [round(o, 1) for o in result["oxygen_accum_ppm"]],
        },
        "assumptions": ASSUMPTIONS,
    }


@router.post("/shelf-life", response_model=ShelfLifeResponse)
def shelf_life_endpoint(payload: ShelfLifeRequest) -> dict:
    store = get_store()
    product = store.get("products", payload.productId)
    if not product:
        raise HTTPException(status_code=404, detail="product not found")

    request = payload.resolved()
    bundle = build_shelf_life(product, request)
    sim = bundle["sim"]
    prediction = bundle["shelfLife"]
    spec = prediction.spec

    store.put(
        "simulations",
        new_id("sim"),
        {
            "productId": product["id"],
            "kind": "shelf_life",
            "status": sim["status"],
            "finalQuality": sim["finalQuality"],
            "predictedShelfLifeDays": prediction.predicted_shelf_life_days,
            "chamberPreset": request.chamberPreset or "Standard",
            "temperatureC": sim["temperatureC"],
            "humidityRH": sim["humidityRH"],
            "layers": sim["layers"],
            "createdAt": now_iso(),
        },
    )

    return {
        "productId": product["id"],
        "predictedShelfLifeDays": prediction.predicted_shelf_life_days,
        "limitingFactor": prediction.limiting_factor,
        "moistureCriticalDay": prediction.moisture_critical_day,
        "pvCurve": [round(v, 4) for v in bundle["pvCurve"]],
        "microbialCurve": [round(v, 4) for v in bundle["microbialCurve"]],
        "qualityCurve": [round(q, 3) for q in sim["quality"]],
        "timeDays": [round(t, 3) for t in sim["time_days"]],
        "thresholds": {
            "qualityPct": prediction.threshold_used,
            "moistureGm2": spec.critical_moisture_g_m2,
            "peroxideValue": spec.pv_limit,
            "microbialLogCfu": spec.critical_log_cfu,
        },
        "disclaimer": (
            "Model output using typical published kinetics — validate with a "
            "stability study before making claims."
        ),
    }


@router.get("/{sim_id}")
def get_simulation(sim_id: str) -> dict:
    simulation = get_store().get("simulations", sim_id)
    if not simulation:
        raise HTTPException(status_code=404, detail="simulation not found")
    return simulation
