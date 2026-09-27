"""Category normalization.

The Flutter form may send either enum keys (``fruitsVegetables``) or human
labels (``Fruits & Vegetables``); the backend accepts both.
"""

from __future__ import annotations

CANONICAL = [
    "snacks",
    "dairy",
    "fruitsVegetables",
    "meatSeafood",
    "bakery",
    "beverages",
    "readyToEat",
    "grainsPulses",
    "others",
]

_ALIASES = {
    "snacks": "snacks",
    "dairy": "dairy",
    "fruitsvegetables": "fruitsVegetables",
    "fruits": "fruitsVegetables",
    "vegetables": "fruitsVegetables",
    "meatseafood": "meatSeafood",
    "meat": "meatSeafood",
    "seafood": "meatSeafood",
    "bakery": "bakery",
    "beverages": "beverages",
    "beverage": "beverages",
    "readytoeat": "readyToEat",
    "ready": "readyToEat",
    "grains": "grainsPulses",
    "grainsandpulses": "grainsPulses",
    "pulses": "grainsPulses",
    "others": "others",
    "other": "others",
}


def normalize_category(value: str | None) -> str:
    if not value:
        return "others"
    key = "".join(ch for ch in value.lower() if ch.isalnum())
    if key in _ALIASES:
        return _ALIASES[key]
    for alias, canonical in _ALIASES.items():
        if alias and alias in key:
            return canonical
    return "others"
