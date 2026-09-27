"""Supplier route tracing: Haversine distance + shipping emissions."""

from __future__ import annotations

import math

from services.lca import FREIGHT_CO2_PER_TONNE_KM

EARTH_RADIUS_KM = 6371.0


def haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    d_phi = math.radians(lat2 - lat1)
    d_lambda = math.radians(lng2 - lng1)
    a = (
        math.sin(d_phi / 2) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(d_lambda / 2) ** 2
    )
    return 2 * EARTH_RADIUS_KM * math.asin(math.sqrt(a))


def route_emissions(
    *,
    distance_km: float,
    mass_kg: float,
    mode: str = "road",
) -> dict:
    """CO2e for shipping ``mass_kg`` over ``distance_km`` by ``mode``."""
    factor = FREIGHT_CO2_PER_TONNE_KM.get(mode, FREIGHT_CO2_PER_TONNE_KM["road"])
    tonnes = mass_kg / 1000.0
    co2e = tonnes * distance_km * factor
    return {
        "distanceKm": round(distance_km, 1),
        "mode": mode,
        "massKg": mass_kg,
        "co2eKg": round(co2e, 4),
        "factorKgCo2ePerTonneKm": factor,
    }
