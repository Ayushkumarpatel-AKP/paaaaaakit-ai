"""Pydantic request/response models for every endpoint.

Field names match the Firestore document shapes in the build spec and the
Flutter client, which parses these responses directly.
"""

from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, Field, field_validator, model_validator

from services.shelf_life import estimate_water_activity

Status = Literal["Optimal", "Warning", "Action Needed"]


# ---------------------------------------------------------------------------
# Products
# ---------------------------------------------------------------------------
class ProductCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=120)
    category: str
    #: Measured water activity. Leave unset to have the backend estimate it from
    #: ``category`` + ``moisturePct`` — the product wizard does not collect Aw.
    waterActivity: float | None = None
    fatContent: float = 0.0
    oxygenSensitivity: str = "medium"
    lightSensitivity: str = "medium"
    targetShelfLifeDays: int
    minTempC: float
    maxTempC: float
    packagingFormat: str
    budgetPer1kUnits: float = 0.0
    userId: str = "demo-user"

    #: Straight from the product wizard, so recommendations can be sized against
    #: the real product instead of a bundled sample.
    moisturePct: float = Field(default=0.0, ge=0.0, le=100.0)
    ph: float = Field(default=7.0, ge=0.0, le=14.0)
    relativeHumidityPct: float = Field(default=60.0, ge=0.0, le=100.0)

    @field_validator("waterActivity")
    @classmethod
    def _aw_range(cls, value: float | None) -> float | None:
        if value is None:
            return None
        if not 0.10 <= value <= 0.99:
            raise ValueError("waterActivity must be between 0.10 and 0.99")
        return value

    @model_validator(mode="after")
    def _fill_water_activity(self) -> "ProductCreate":
        """Guarantee a concrete Aw so downstream physics never sees ``None``."""
        if self.waterActivity is None:
            self.waterActivity = estimate_water_activity(
                self.category, self.moisturePct
            )
        return self

    @field_validator("targetShelfLifeDays")
    @classmethod
    def _shelf_life_positive(cls, value: int) -> int:
        if value <= 0:
            raise ValueError("targetShelfLifeDays must be greater than 0")
        return value

    @model_validator(mode="after")
    def _temp_range(self) -> "ProductCreate":
        if self.maxTempC <= self.minTempC:
            raise ValueError("maxTempC must be greater than minTempC")
        return self


class Product(ProductCreate):
    id: str
    createdAt: str


# ---------------------------------------------------------------------------
# Simulation
# ---------------------------------------------------------------------------
class GasMix(BaseModel):
    o2: float = 21.0
    co2: float = 0.0
    n2: float = 79.0


CHAMBER_PRESETS: dict[str, dict] = {
    "Standard": {"temperatureC": 23.0, "humidityRH": 50.0, "gasMix": {"o2": 21.0, "co2": 0.0, "n2": 79.0}},
    "Tropical": {"temperatureC": 38.0, "humidityRH": 85.0, "gasMix": {"o2": 21.0, "co2": 0.0, "n2": 79.0}},
    "Cold Chain": {"temperatureC": 4.0, "humidityRH": 75.0, "gasMix": {"o2": 21.0, "co2": 0.0, "n2": 79.0}},
    "Arid": {"temperatureC": 35.0, "humidityRH": 15.0, "gasMix": {"o2": 21.0, "co2": 0.0, "n2": 79.0}},
}


class SimulationRequest(BaseModel):
    productId: str
    chamberPreset: str | None = None
    temperatureC: float | None = None
    humidityRH: float | None = None
    gasMix: GasMix | None = None
    barrierThicknessUm: float | None = None
    durationDays: float = 180.0
    layers: list[dict] | None = None

    def resolved(self) -> "SimulationRequest":
        """Apply chamber-preset defaults for any field the client omitted."""
        preset = CHAMBER_PRESETS.get(self.chamberPreset or "Standard", CHAMBER_PRESETS["Standard"])
        data = self.model_dump()
        if self.temperatureC is None:
            data["temperatureC"] = preset["temperatureC"]
        if self.humidityRH is None:
            data["humidityRH"] = preset["humidityRH"]
        if self.gasMix is None:
            data["gasMix"] = preset["gasMix"]
        return SimulationRequest(**data)


class SimulationResponse(BaseModel):
    simId: str
    productId: str
    chamberPreset: str
    temperatureC: float
    humidityRH: float
    gasMix: GasMix
    barrierThicknessUm: float
    durationDays: float
    status: Status
    finalQuality: float
    otr: float
    mvtr: float
    predictedShelfLifeDays: float | None = None
    resultTimeSeries: dict[str, list[float]]
    assumptions: list[str] = []


class ShelfLifeRequest(SimulationRequest):
    qualityThreshold: float | None = None


class ShelfLifeResponse(BaseModel):
    productId: str
    predictedShelfLifeDays: float
    limitingFactor: str
    moistureCriticalDay: float | None
    pvCurve: list[float]
    microbialCurve: list[float]
    qualityCurve: list[float]
    timeDays: list[float]
    thresholds: dict[str, float]
    disclaimer: str


# ---------------------------------------------------------------------------
# Recommendations
# ---------------------------------------------------------------------------
class RecommendationRequest(BaseModel):
    productId: str


class RecommendationTier(BaseModel):
    structure: str
    mvtr_g_m2_day: float
    otr_cc_m2_day: float
    #: INR (₹) per 1,000 units
    cost_per_1k: float
    #: INR (₹) per single pack
    cost_per_unit: float | None = None
    carbon_kgco2e_per_kg: float
    layers: list[dict] = []
    totalThicknessUm: float | None = None
    tier: str | None = None
    rationale: str | None = None


class RecommendationResponse(BaseModel):
    recId: str
    productId: str
    cost_optimized: RecommendationTier
    sustainability_first: RecommendationTier
    max_barrier: RecommendationTier
    used_llm: bool
    disclaimer: str
    createdAt: str


# ---------------------------------------------------------------------------
# Audit
# ---------------------------------------------------------------------------
class Defect(BaseModel):
    type: str
    severity: str
    description: str


class AuditResponse(BaseModel):
    auditId: str
    productId: str | None = None
    imageUrl: str | None = None
    layer_analysis: dict[str, str]
    defects: list[Defect]
    ric_code: str | None = None
    compliance_note: str
    used_llm: bool
    disclosure: str
    createdAt: str


# ---------------------------------------------------------------------------
# Layer stack
# ---------------------------------------------------------------------------
class LayerInput(BaseModel):
    material: str
    thicknessUm: float = Field(gt=0)


class LayerStackRequest(BaseModel):
    layers: list[LayerInput]
    areaM2: float = 0.05
    units: int = 1000
    productId: str | None = None


class LayerStackResponse(BaseModel):
    stackId: str | None = None
    layers: list[dict]
    totalThickness: float
    seriesOTR: float
    seriesMVTR: float
    seriesCO2TR: float
    stackWeight: float
    stackWeightPerM2: float
    estimatedCost: float
    recyclabilityScore: float


# ---------------------------------------------------------------------------
# LCA
# ---------------------------------------------------------------------------
class LcaRequest(BaseModel):
    layers: list[LayerInput]
    areaM2: float = 0.05
    productionVolume: int = 1000
    transportDistanceKm: float = 0.0
    freightMode: str = "road"
    #: Indian market by default; all monetary output is INR (₹).
    jurisdiction: str = "IN"
    productId: str | None = None


# ---------------------------------------------------------------------------
# Suppliers
# ---------------------------------------------------------------------------
class RfqRequest(BaseModel):
    material: str | None = None
    quantityKg: float | None = None
    message: str | None = None
    contactEmail: str | None = None


# ---------------------------------------------------------------------------
# Chat
# ---------------------------------------------------------------------------
class ChatRequest(BaseModel):
    sessionId: str
    message: str
    productId: str | None = None
    simId: str | None = None


class ChatResponse(BaseModel):
    sessionId: str
    role: str = "assistant"
    content: str
    used_llm: bool
    timestamp: str
