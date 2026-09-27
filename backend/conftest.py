"""Pytest configuration: put the backend package on sys.path and reset state."""

from __future__ import annotations

import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

os.environ.setdefault("STORAGE_BACKEND", "memory")
os.environ.pop("OPENAI_API_KEY", None)

from services.store import reset_store  # noqa: E402


@pytest.fixture(autouse=True)
def _fresh_store():
    reset_store()
    yield
    reset_store()


@pytest.fixture
def client():
    from fastapi.testclient import TestClient

    from main import app

    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture
def sample_product_payload() -> dict:
    return {
        "name": "Potato Chips",
        "category": "snacks",
        "waterActivity": 0.25,
        "fatContent": 35.0,
        "oxygenSensitivity": "high",
        "lightSensitivity": "high",
        "targetShelfLifeDays": 180,
        "minTempC": 15.0,
        "maxTempC": 30.0,
        "packagingFormat": "Laminate pouch (metallized)",
        "budgetPer1kUnits": 42.0,
    }
