"""End-to-end API tests. No LLM key is set, so fallbacks must keep everything working."""

from __future__ import annotations


def _create_product(client, payload) -> dict:
    response = client.post("/products", json=payload)
    assert response.status_code == 200, response.text
    return response.json()


def test_health_reports_storage_and_llm(client):
    body = client.get("/health").json()
    assert body["status"] == "ok"
    assert body["checks"]["storage"]["backend"] == "memory"
    assert body["checks"]["llm"]["configured"] is False


def test_product_validation_rejects_bad_input(client, sample_product_payload):
    bad = {**sample_product_payload, "waterActivity": 1.4}
    assert client.post("/products", json=bad).status_code == 422

    bad_temp = {**sample_product_payload, "minTempC": 30, "maxTempC": 10}
    assert client.post("/products", json=bad_temp).status_code == 422

    bad_shelf = {**sample_product_payload, "targetShelfLifeDays": 0}
    assert client.post("/products", json=bad_shelf).status_code == 422


def test_water_activity_is_derived_when_not_measured(client, sample_product_payload):
    """The wizard does not collect Aw, so the backend must estimate it."""
    payload = {k: v for k, v in sample_product_payload.items() if k != "waterActivity"}

    # A dry snack follows its moisture content.
    dry = _create_product(client, {**payload, "moisturePct": 3.0})
    assert 0.10 <= dry["waterActivity"] <= 0.99
    assert dry["waterActivity"] < 0.5

    # A wet family is pinned near pure water whatever the moisture figure says.
    wet = _create_product(
        client, {**payload, "category": "dairy", "moisturePct": 88.0}
    )
    assert wet["waterActivity"] > 0.9

    # An explicit measurement always wins over the estimate.
    measured = _create_product(client, {**payload, "waterActivity": 0.42})
    assert measured["waterActivity"] == 0.42


def test_product_accepts_wizard_measurements(client, sample_product_payload):
    product = _create_product(
        client,
        {
            **sample_product_payload,
            "moisturePct": 2.5,
            "ph": 6.2,
            "relativeHumidityPct": 75.0,
            "budgetPer1kUnits": 38.0,
        },
    )
    assert product["moisturePct"] == 2.5
    assert product["ph"] == 6.2
    assert product["relativeHumidityPct"] == 75.0
    assert product["budgetPer1kUnits"] == 38.0

    # Out-of-range measurements are still rejected.
    assert (
        client.post("/products", json={**sample_product_payload, "ph": 20}).status_code
        == 422
    )
    assert (
        client.post(
            "/products", json={**sample_product_payload, "moisturePct": 140}
        ).status_code
        == 422
    )


def test_product_created_and_fetchable(client, sample_product_payload):
    product = _create_product(client, sample_product_payload)
    assert product["id"].startswith("prod_")
    assert product["category"] == "snacks"

    fetched = client.get(f"/products/{product['id']}").json()
    assert fetched["name"] == "Potato Chips"

    assert client.get("/products/does-not-exist").status_code == 404


def test_digital_twin_and_shelf_life(client, sample_product_payload):
    product = _create_product(client, sample_product_payload)

    sim = client.post(
        "/simulate/digital-twin",
        json={
            "productId": product["id"],
            "chamberPreset": "Tropical",
            "durationDays": 180,
        },
    )
    assert sim.status_code == 200, sim.text
    body = sim.json()
    series = body["resultTimeSeries"]
    assert len(series["time"]) == len(series["quality"]) == len(series["moistureGain"])
    assert body["status"] in {"Optimal", "Warning", "Action Needed"}
    assert body["predictedShelfLifeDays"] > 0

    saved = client.get(f"/simulate/{body['simId']}").json()
    assert saved["productId"] == product["id"]

    shelf = client.post(
        "/simulate/shelf-life",
        json={"productId": product["id"], "chamberPreset": "Tropical"},
    )
    assert shelf.status_code == 200, shelf.text
    shelf_body = shelf.json()
    assert shelf_body["predictedShelfLifeDays"] > 0
    assert shelf_body["limitingFactor"] in {
        "quality",
        "moisture",
        "oxidation",
        "microbial",
    }
    assert len(shelf_body["pvCurve"]) == len(shelf_body["microbialCurve"])

    # A gentle chamber with nothing failing inside the window reports "none".
    gentle = client.post(
        "/simulate/shelf-life",
        json={"productId": product["id"], "chamberPreset": "Cold Chain"},
    ).json()
    assert gentle["limitingFactor"] in {"none", "microbial", "moisture"}


def test_simulation_unknown_product_404(client):
    response = client.post("/simulate/digital-twin", json={"productId": "nope"})
    assert response.status_code == 404


def test_recommendations_fall_back_without_key(client, sample_product_payload):
    product = _create_product(client, sample_product_payload)
    response = client.post("/recommendations/generate", json={"productId": product["id"]})
    assert response.status_code == 200, response.text
    body = response.json()

    assert body["used_llm"] is False
    for tier in ("cost_optimized", "sustainability_first", "max_barrier"):
        assert body[tier]["structure"]
        assert body[tier]["otr_cc_m2_day"] > 0
        assert body[tier]["layers"]

    latest = client.get(f"/recommendations/{product['id']}").json()
    assert latest["id"] == body["id"]


def test_layerstack_recalculate(client):
    response = client.post(
        "/layerstack/recalculate",
        json={
            "layers": [
                {"material": "PET (12 um)", "thicknessUm": 12},
                {"material": "Metallized PET", "thicknessUm": 12},
                {"material": "LDPE", "thicknessUm": 75},
            ],
            "areaM2": 0.05,
            "units": 1000,
        },
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["totalThickness"] == 99
    assert body["seriesOTR"] > 0
    assert body["stackWeight"] > 0
    assert 0 <= body["recyclabilityScore"] <= 100


def test_lca_calculate_and_jurisdictions(client, sample_product_payload):
    product = _create_product(client, sample_product_payload)
    response = client.post(
        "/lca/calculate",
        json={
            "layers": [
                {"material": "pet", "thicknessUm": 12},
                {"material": "ldpe", "thicknessUm": 60},
            ],
            "areaM2": 0.05,
            "productionVolume": 10000,
            "transportDistanceKm": 1200,
            "jurisdiction": "EU",
            "productId": product["id"],
        },
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["carbonFootprintKgCO2e"] > 0
    assert body["waterUsageL"] > 0
    assert body["costBreakdown"]["per_1k_units"]["total"] > 0
    assert body["eprTaxComparison"]["jurisdiction"] == "EU"

    assert client.get("/lca/jurisdictions").json()["ratesPerKg"]["EU"] > 0
    assert len(client.get("/lca/materials").json()) >= 10


def test_audit_without_vision_key_returns_schema_valid_payload(client, sample_product_payload):
    product = _create_product(client, sample_product_payload)
    response = client.post(
        "/audit/analyze",
        files={"image": ("pouch.jpg", b"\xff\xd8\xff\xe0fake-jpeg", "image/jpeg")},
        data={"productId": product["id"]},
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["used_llm"] is False
    assert set(body["layer_analysis"]) == {
        "outer_substrate",
        "core_barrier",
        "food_contact_liner",
    }
    assert body["defects"] == []
    assert body["ric_code"] is None
    assert "not a certified" in body["compliance_note"].lower()


def test_audit_rejects_empty_upload(client):
    response = client.post(
        "/audit/analyze",
        files={"image": ("empty.jpg", b"", "image/jpeg")},
    )
    assert response.status_code == 400


def test_chat_fallback_and_history(client, sample_product_payload):
    product = _create_product(client, sample_product_payload)
    sim = client.post(
        "/simulate/digital-twin", json={"productId": product["id"], "chamberPreset": "Tropical"}
    ).json()

    response = client.post(
        "/chat/message",
        json={
            "sessionId": "sess-1",
            "message": "Why is EVOH a good oxygen barrier?",
            "productId": product["id"],
            "simId": sim["simId"],
        },
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["used_llm"] is False
    assert "series permeability" in body["content"]
    assert body["context"]["lastQuality"] != "n/a"

    turns = client.get("/chat/sess-1/messages").json()
    assert len(turns) == 2
    assert turns[0]["role"] == "user"
    assert turns[1]["role"] == "assistant"


def test_suppliers_filter_trace_and_rfq(client):
    response = client.get("/suppliers", params={"material": "evoh"})
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["count"] >= 1
    supplier = body["suppliers"][0]
    assert supplier["distanceKm"] >= 0
    assert supplier["route"]["co2eKg"] >= 0
    assert supplier["certifications"]

    filtered = client.get("/suppliers", params={"certification": "FSC"}).json()
    assert all(
        any("fsc" in cert.lower() for cert in s["certifications"])
        for s in filtered["suppliers"]
    )

    rfq = client.post(
        f"/suppliers/{supplier['id']}/rfq",
        json={"material": "evoh", "quantityKg": 500, "contactEmail": "buyer@example.com"},
    )
    assert rfq.status_code == 200, rfq.text
    assert "Request sent" in rfq.json()["confirmation"]

    assert client.post("/suppliers/nope/rfq", json={}).status_code == 404


def test_dashboard_and_history(client, sample_product_payload):
    product = _create_product(client, sample_product_payload)
    client.post("/simulate/digital-twin", json={"productId": product["id"]})
    client.post("/recommendations/generate", json={"productId": product["id"]})

    summary = client.get("/dashboard/summary").json()
    assert summary["activeProjectCount"] == 1
    assert summary["avgEcoScore"] > 0

    feed = client.get("/dashboard/recent-feed").json()
    assert len(feed) == 1
    assert feed[0]["productName"] == "Potato Chips"

    history = client.get("/history", params={"search": "Potato"}).json()
    assert history["count"] == 1

    empty = client.get("/history", params={"search": "not-a-product"}).json()
    assert empty["count"] == 0


def test_report_export_produces_pdf(client, sample_product_payload):
    product = _create_product(client, sample_product_payload)
    client.post("/simulate/digital-twin", json={"productId": product["id"]})

    response = client.post(f"/reports/export/{product['id']}")
    assert response.status_code == 200, response.text
    assert response.headers["content-type"] == "application/pdf"
    assert response.content.startswith(b"%PDF")

    assert client.post("/reports/export/missing").status_code == 404
