# PackIT AI — Backend

FastAPI service behind the Flutter app. Real physics where it matters
(Arrhenius kinetics, series permeability, shelf-life models, LCA), LLM-assisted
where it helps (recommendations, chat, vision audit).

## Run it

```bash
cd backend
python -m pip install -r requirements.txt     # deps
uvicorn main:app --reload --port 8000         # http://localhost:8000/docs
```

Runs with **zero secrets**: data lives in memory and the LLM endpoints fall back
to deterministic rule-based answers. Point the Flutter app at it with
`--dart-define=API_BASE_URL=http://<host>:8000`.

## Tests

```bash
cd backend
python -m pip install -r requirements-dev.txt
python -m pytest -q
```

## Configuration (all optional)

| Env var | Default | Purpose |
| --- | --- | --- |
| `STORAGE_BACKEND` | `memory` | `memory` or `firestore` |
| `GOOGLE_APPLICATION_CREDENTIALS` / `FIRESTORE_PROJECT` | — | Firestore auth |
| `OPENAI_API_KEY` | — | enables the LLM proxy (any OpenAI-compatible key) |
| `OPENAI_BASE_URL` | `https://api.openai.com/v1` | OpenAI / gateway / local vLLM |
| `LLM_MODEL` / `VISION_MODEL` | `gpt-4o-mini` | text + vision model |
| `CORS_ORIGINS` | `*` | comma-separated allowed origins |
| `SEED_SUPPLIERS` | `true` | seed the sample supplier directory |
| `PLANT_LAT` / `PLANT_LNG` / `PLANT_LABEL` | Ahmedabad, India | route-tracing origin |

## Endpoints

| Method | Path | Notes |
| --- | --- | --- |
| GET | `/health` | storage reachable + LLM configured (splash pings this) |
| POST/GET | `/products`, `/products/{id}` | server-side validation mirrors Flutter |
| POST | `/simulate/digital-twin` | Arrhenius + moisture + oxygen time series |
| POST | `/simulate/shelf-life` | earliest of quality/moisture/oxidation/microbial |
| POST | `/recommendations/generate` | 3 tiers, strict-JSON LLM + DB-grounded fallback |
| POST | `/audit/analyze` | multipart image → strict-JSON vision result |
| POST | `/layerstack/recalculate` | series permeability, mass, cost |
| POST | `/lca/calculate` | cost, carbon, water, recyclability, EPR |
| GET | `/suppliers`, `/suppliers/{id}` | filter + Haversine route emissions |
| POST | `/suppliers/{id}/rfq` | logs to `rfq_requests` |
| POST | `/chat/message` | live product/simulation context injection |
| GET | `/dashboard/summary`, `/dashboard/recent-feed` | aggregates `project_summary` |
| GET | `/history` | search/filter over `project_summary` |
| POST | `/reports/export/{projectId}` | server-side PDF |

## How honest is each screen?

* **Digital Twin, Shelf Life, Layer Stack, LCA** — real formulas
  (`solve_ivp`, `1/TR = Σ d_i/P_i`, logistic microbial growth, Arrhenius
  oxidation). Kinetics/permeabilities are **typical published ranges**, not
  proprietary lab data.
* **Recommendations & Chat** — LLM-generated, grounded in the same material
  database. Label it "AI-assisted engineering guidance", not lab-certified data.
* **Auditor** — an **AI visual estimate**, not a certified compliance
  inspection. The prompt forbids guessing and the response carries a disclosure.

## Layout

```
main.py                 app + /health + router wiring + supplier seeding
config.py               env-driven settings (no-key-safe defaults)
routers/                one module per screen's endpoints
services/               material_db, arrhenius, permeability, shelf_life,
                        lca, digital_twin, llm_client, prompts, fallback,
                        store, projects, traceability, categories
models/schemas.py       Pydantic request/response contracts
data/seed_suppliers.py  synthetic supplier directory
tests/                  physics + end-to-end API tests
```
