"""Series permeability + transport for multilayer packaging stacks.

Every layer is a resistor in series::

    1 / TR_total = sum(d_i / P_i)

so ``TR_total = 1 / sum(d_i / P_i)`` where ``d_i`` is microns and ``P_i`` is the
material's intrinsic permeability (see ``material_db``). This is the single
implementation shared by the layer-stack customizer, the digital twin's oxygen
accumulation and the shelf-life moisture curve.
"""

from __future__ import annotations

from dataclasses import dataclass

from services.material_db import Material, find_material


@dataclass
class LayerSpec:
    """A single resolved layer."""

    key: str
    name: str
    thickness_um: float
    material: Material


@dataclass
class StackPermeability:
    #: cc / (m^2 * day) at 1 atm driving force
    otr: float
    #: g / (m^2 * day)
    mvtr: float
    #: cc / (m^2 * day) at 1 atm driving force
    co2tr: float
    total_thickness_um: float
    #: kg per unit area (kg / m^2)
    mass_per_m2: float
    layers: list[LayerSpec]


def resolve_layers(layers: list) -> list[LayerSpec]:
    """Accept dicts (``{"material", "thicknessUm"}``) or objects; resolve names."""
    resolved: list[LayerSpec] = []
    for layer in layers:
        if isinstance(layer, dict):
            raw_name = layer.get("material") or layer.get("name")
            thickness = layer.get("thicknessUm", layer.get("thickness_um", 0))
        else:
            raw_name = getattr(layer, "material", getattr(layer, "name", None))
            thickness = getattr(
                layer, "thicknessUm", getattr(layer, "thickness_um", 0)
            )
        mat = find_material(raw_name)
        resolved.append(
            LayerSpec(
                key=mat.key,
                name=raw_name or mat.name,
                thickness_um=float(thickness or 0.0),
                material=mat,
            )
        )
    return resolved


def series_transmission(
    layers: list,
    *,
    area_m2: float = 1.0,
) -> StackPermeability:
    """Compute the stack's series transmission rates and areal mass.

    ``area_m2`` only affects ``mass_per_m2`` indirectly (it cancels); the mass is
    reported per square metre so callers scale by their own package area.
    """
    resolved = resolve_layers(layers)
    if not resolved:
        return StackPermeability(0.0, 0.0, 0.0, 0.0, 0.0, [])

    def resistance(attr: str) -> float:
        total = 0.0
        for layer in resolved:
            perm = getattr(layer.material, attr)
            if layer.thickness_um <= 0 or perm <= 0:
                continue
            total += layer.thickness_um / perm
        return total

    def transmission(attr: str) -> float:
        r = resistance(attr)
        return 0.0 if r <= 0 else 1.0 / r

    # kg/m^2 = sum(thickness_um * 1e-6 m * density_g_cm3 * 1000 kg/m^3)
    mass_per_m2 = sum(
        layer.thickness_um * 1e-3 * layer.material.density for layer in resolved
    )
    return StackPermeability(
        otr=transmission("otr"),
        mvtr=transmission("mvtr"),
        co2tr=transmission("co2tr"),
        total_thickness_um=sum(layer.thickness_um for layer in resolved),
        mass_per_m2=mass_per_m2,
        layers=resolved,
    )


def thickness_correction(thickness_um: float, reference_um: float = 50.0) -> float:
    """Simple Fickian scaling: transmission is inversely proportional to thickness.

    Returns a multiplier relative to the reference thickness (1.0 => no change).
    """
    if thickness_um <= 0:
        return 1.0
    return max(reference_um / thickness_um, 1e-3)
