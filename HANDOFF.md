# HANDOFF — Make AI packaging recommendations genuinely product-specific

> **For the next agent:** this file is the single source of truth for an
> in-progress task. Read it fully before touching code. Update the
> **STATUS** table after every task and commit that update together with the
> task's code. Commits are auto-pushed by `.githooks/post-commit`.

Last updated: task 4 complete.

---

## 1. The problem (verified by reading the code, not assumed)

The app advertises an "AI packaging recommendation", but the recommendation is
**not** based on the user's product. Five concrete defects, all confirmed:

### 1.1 The wizard collects real data that is then thrown away
`lib/screens/product_input_screen.dart:96-113` sends a rich payload:
`name, category, moisture, oilFat, ph, expectedShelfLife, shelfLifeUnit,
transportDistance, budgetMin, budgetMax, budgetUnit, specialIngredients`.

`lib/main.dart` → `_registerProduct()` (~line 108) discards most of it and
rebuilds the backend spec from a **hardcoded sample product**:

```dart
final matched = SampleData.products.firstWhere(
  (p) => p.name.toLowerCase().contains(productName.toString().toLowerCase()),
  orElse: () => SampleData.products[0],          // <- silently becomes Potato Chips
);
await AppSession.instance.api.createProduct({
  'category': matched.category.name,             // <- SAMPLE, not the user's dropdown
  'waterActivity': matched.waterActivity...,     // <- SAMPLE, moisture input ignored
  'fatContent': completeData['oilFat'] ?? ...,   // user value (the only one used)
  'oxygenSensitivity': highSensitivity ? ... ,   // hardcoded category set
  'lightSensitivity': highSensitivity ? ... ,    // hardcoded category set
  'budgetPer1kUnits': 40.0,                      // <- HARDCODED, budget input ignored
});
```

Only 5 samples exist (`lib/data/sample_data.dart`): Potato Chips, Dried Mango
Chips, Pasteurized Milk, Fresh Tomatoes, Fresh Prime Beef. Any unrecognised
product name becomes Potato Chips, and every downstream number follows.

### 1.2 The three tiers are fixed templates
`backend/services/fallback.py` → `RECOMMENDATION_TEMPLATES` is three hardcoded
layer stacks (`cost_optimized` = PET/met-PET/LDPE, `sustainability_first` =
PLA/nanocellulose/PLA, `max_barrier` = PET/AlOx-PET/EVOH/LDPE). They are
identical for chips, milk and beef.

Even with an LLM key configured, `backend/routers/recommend.py:44`
(`_merge_with_fallback`) takes `layers` from the DB templates — the LLM only
names the structure and may override `otr/mvtr/cost/carbon`.

### 1.3 LLM is off in this environment
`OPENAI_API_KEY` is unset and there is no `backend/.env`, so
`backend/config.py:65` (`llm_enabled`) is False and every request takes the
deterministic fallback path. When describing the feature, do not claim a model
is involved unless the key is set.

### 1.4 Client-side numbers that look computed but are constants
`lib/screens/recommendation_result_screen.dart`:
- `_calculateConfidence()` (line ~131) starts at 70 and adds 5 per non-zero
  field → always 70-90. It is not a model confidence.
- `matchScore: 95`, `'Best Match'`, `shelfLife: '6 Months'`,
  `protection: '95%'`, `sealability`, `mechanical` are literals in
  `_packagingOptions` and are **never** overwritten by `_applyTier()`.
- `_analyzeProduct()` (line ~104) derives "risks" from `widget.product` (the
  matched *sample*), not from the user's inputs.

### 1.5 Tier → card mismatch
`_loadRecommendations()` (line ~86) maps
`_applyTier(1, reco['sustainability_first'])`, but card index 1 is
`'subtitle': 'Recommended (MET)'` with `isRecommended: true` and is the
default-selected card (`_selectedOptionIndex = 1`). So the "Best Match" card
actually holds the compostable PLA stack.

---

## 2. What already exists and should be REUSED (do not rewrite)

The physics is already good. The fix is to *drive it from the user's product*
and *solve* for stacks instead of picking templates.

| Piece | Location | What it gives |
|---|---|---|
| Material database | `backend/services/material_db.py` | 14 materials with `otr`, `mvtr`, `co2tr`, `density`, `cost_per_kg`, aliases; `find_material()` |
| Series permeability | `backend/services/permeability.py` | `series_transmission(layers)` → `otr`, `mvtr`, `co2tr`, `total_thickness_um`, `mass_per_m2`. Implements `1/TR = Σ(dᵢ/Pᵢ)` |
| Shelf-life engine | `backend/services/shelf_life.py` | `category_spec()` (9 categories with `quality_threshold`, `critical_moisture_g_m2`, `pv_limit`, `critical_log_cfu`, `microbial_r_ref`, `equilibrium_rh_pct`), `moisture_gain_curve()`, `peroxide_value_curve()`, `oxygen_consumption_ppm_per_day()`, `microbial_curve()`, `predict_shelf_life()` |
| LCA / cost | `backend/services/lca.py` | `cost_breakdown()`, `carbon_footprint()`, `recyclability_score()`, `eco_stack_suggestion()` |
| Cost+barrier helper | `backend/services/fallback.py` → `stack_metrics(layers)` | One call returning structure string, otr, mvtr, cost per unit / per 1k, carbon per kg, layers, total thickness |
| Product schema | `backend/models/schemas.py:19` `ProductCreate` | **Already has** `budgetPer1kUnits` (ignored today). Needs `moisturePct`, `ph`, `relativeHumidityPct` |
| Category normalisation | `backend/services/categories.py` | Accepts enum keys (`fruitsVegetables`) or labels |

Material keys available: `pet, met_pet, ldpe, hdpe, bopp, pp, alu_foil, evoh,
alox_pet, pla, nanocellulose, paperboard, ionomer, bio_coating`.

---

## 3. Plan — tasks, in order

Each task ends with a commit (subject line given below). Update the STATUS
table and commit the update with the task.

### Task 1 — Flutter: stop discarding the user's inputs
`lib/main.dart`, `_registerProduct()` (+ the `storage_conditions` callback above it).
- Build the backend product spec from `completeData`, not from `matched`.
- Category: use `completeData['category']` (a `FoodCategory` enum) → `.name`.
- Send `moisture`, `ph`, the user's `budgetMax`/`budgetUnit`, storage RH and
  temperature. `waterActivity` must be derived — see Task 2 note.
- Sensitivity flags: derive from the product's own numbers (fat %, pH,
  moisture) instead of the hardcoded `{meatSeafood, dairy, readyToEat, bakery}` set.
- Keep the `SampleData` fallback **only** for offline/`_currentProduct` display.
- Commit subject: `Drive product spec from the wizard inputs, not sample data`

### Task 2 — Backend: accept the real product data
`backend/models/schemas.py` → `ProductCreate`.
- Add optional `moisturePct: float = 0.0`, `ph: float = 7.0`,
  `relativeHumidityPct: float = 60.0`.
- Optional `waterActivity`: the wizard does not measure Aw. Derive it in the
  backend from `moisturePct` + category when the client omits it (a documented
  approximation, e.g. high-moisture/dairy → 0.97-0.99, dry snacks → 0.2-0.4),
  and keep the client able to send an explicit value.
- Commit subject: `Accept moisture, pH and storage RH on the product schema`

### Task 3 — Backend: solve for a stack instead of using templates
New `backend/services/stack_solver.py` (+ tests in `backend/tests/`).
- **Step A — target requirement.** From `category_spec()`, the product's
  `targetShelfLifeDays`, storage temp/RH and fat content, compute the maximum
  allowed MVTR and OTR that still keep moisture gain under
  `critical_moisture_g_m2`, peroxide value under `pv_limit`, and microbes under
  `critical_log_cfu` for the whole target life. Reuse `shelf_life.py` rather
  than re-deriving formulas.
- **Step B — search.** Enumerate realistic flexible-laminate structures:
  outer (print) × barrier core × sealant from `material_db`, with a small
  thickness grid per material. Compute `series_transmission` + `cost_breakdown`
  + `recyclability_score` for each candidate.
- **Step C — pick three tiers** from the *feasible* set (meet both targets):
  - `cost_optimized` = cheapest feasible ≤ `budgetPer1kUnits` (when > 0)
  - `sustainability_first` = best recyclability/compostable feasible
  - `max_barrier` = lowest combined transmission (largest safety margin)
- If nothing is feasible, return the closest stack **and say so** (do not
  silently return a template).
- Return per tier: `structure`, `layers`, `otr`, `mvtr`, `cost_per_1k`,
  `cost_per_unit`, `carbon`, `totalThicknessUm`, plus new honest fields:
  `meets_target: bool`, `predicted_shelf_life_days`, `limiting_factor`,
  `required_mvtr`, `required_otr`, `target_margin`, and a plain-language
  `rationale`. Suggested `why` list explaining the chosen materials.
- Commit subject: `Solve packaging stacks against the product's barrier targets`

### Task 4 — Backend: use the solver in the endpoint
`backend/routers/recommend.py`.
- Replace `recommendations_for()` with the solver, passing the stored product.
- Keep the LLM path but scope it to *explaining* the solver's result (and
  optional structure naming) — never let it invent the numbers. Keep
  `used_llm` accurate.
- Keep `_merge_with_fallback` only as a schema guard.
- Commit subject: `Serve solver-derived recommendations from the API`

### Task 5 — Flutter: show real values, delete the fake ones
`lib/screens/recommendation_result_screen.dart`.
- Fix the tier→card mapping and the `'Recommended (MET)'` label so the card
  matches the tier it holds.
- Replace `matchScore: 95` / `'Best Match'` / `protection` / `shelfLife` /
  `sealability` / `mechanical` literals with values from the API response
  (`meets_target`, `predicted_shelf_life_days`, `target_margin`).
- Replace `_calculateConfidence()` with an honest "data completeness" or
  "target margin" indicator, and drop the 70-90 fake score.
- Drive `_analyzeProduct()` off the response / the user's own inputs, not
  `widget.product` (the sample).
- Show `limiting_factor`, `required_mvtr`/`required_otr` and the tier `why`
  list so the reasoning is visible.
- Commit subject: `Show solver-derived values on the recommendation screen`

### Task 6 — Verify and document
- `cd backend && python -m pytest`
- `flutter analyze` (2 pre-existing warnings in
  `recommendation_result_screen.dart` for an unused import/field should be
  resolved by Task 5 — if they persist, they are still pre-existing)
- `flutter test`
- Update this file's STATUS + "Notes for the next agent", commit.
- Commit subject: `Verify product-specific recommendations end to end`

### Optional / later
- `PackIT_AI_v1.0.apk` is committed at the repo root (54.6 MB). Rebuild with
  `flutter build apk --release` and copy `build/app/outputs/flutter-apk/app-release.apk`
  over it if the shipped APK must include these changes. GitHub warns above
  50 MB; the hard limit is 100 MB.
- `lib/screens/packaging_customizer_screen.dart` still has a cosmetic
  form-factor filter (`PackagingFormFactor.values.take(3)` / `skip(1)`).
- Mockup families are wired for `snacks`→chips and `dairy`/`beverages`→milk;
  other categories fall back to the full catalogue
  (`lib/data/mockup_library.dart`).

---

## 4. STATUS

| # | Task | Status | Commit |
|---|---|---|---|
| 0 | Handoff document | **DONE** | `1a90e0d` |
| 1 | Flutter: use wizard inputs | **DONE** | (this commit) |
| 2 | Backend: extend product schema | **DONE** | (this commit) |
| 3 | Backend: stack solver | **DONE** | (this commit) |
| 4 | Backend: wire into /recommendations | **DONE** | (this commit) |
| 5 | Flutter: real values on result screen | TODO | |
| 6 | Verify + document | TODO | |

### Task 1 notes (for the next agent)

Done in `lib/main.dart`:
- `_registerProduct()` now builds the `POST /products` spec from
  `completeData` (the wizard + storage screens) instead of the matched sample.
- New helpers: `_categoryFrom()`, `_estimateWaterActivity()`,
  `_productFromInputs()`, `_closestSample()`.
- Sample lookup is now fallback-only. `_navigateTo('recommendation_result',
  arguments: described)` passes the **user's** product, so the result screen and
  the mockup family follow the category the user picked. Typing "biscuits" and
  choosing Bakery no longer silently becomes Potato Chips.
- **Fixed a second silent bug:** `_resolveShelfLifeDays()` read
  `desiredShelfLife`, but the wizard writes `expectedShelfLife`, so the shelf
  life slider was dead and every product got the 6-month default. Now reads
  `expectedShelfLife` with the old key as a fallback.
- Sensitivity flags are derived from fat %/moisture/temp instead of the
  hardcoded `{meatSeafood, dairy, readyToEat, bakery}` set.
- `budgetPer1kUnits` now sends the user's `budgetMax` (was hardcoded `40.0`).
- Also sends `moisturePct`, `ph`, `relativeHumidityPct`. Pydantic ignores
  unknown fields today, so this is safe **before** Task 2 lands — but those
  values do nothing until Task 2 adds them to `ProductCreate`.

Verified: `flutter analyze` clean (same 2 pre-existing warnings), `flutter test` passes.

Still true after Task 1: the backend still returns the three fixed templates
(`fallback.py`), so the *stacks* are not yet product-specific — that is Task 3/4.
The result screen still shows the hardcoded `matchScore` / `protection` /
`shelfLife` literals — that is Task 5.

One approximation to be aware of: `waterActivity` is estimated from category +
moisture content (`_estimateWaterActivity`) because the wizard has no Aw input.
Task 2 should move that derivation to the backend so the API owns it.

### Task 2 notes (for the next agent)

Done:
- `backend/services/shelf_life.py` → new `estimate_water_activity(category,
  moisture_pct)`. Perishable families (`dairy, beverages, meatSeafood,
  readyToEat, fruitsVegetables`) return 0.97; dry/semi-dry families map from
  moisture content via `0.20 + moisturePct * 0.03`, clamped to 0.10-0.95.
- `backend/models/schemas.py` → `ProductCreate` gains `moisturePct`, `ph`,
  `relativeHumidityPct` (all range-validated) and `waterActivity` is now
  `float | None = None` with a `model_validator(mode="after")` that fills it
  from `estimate_water_activity()`. An explicit measured value still wins, and
  out-of-range explicit values are still rejected with 422 (existing test kept).
- `backend/models/schemas.py` now imports `services.shelf_life` — verified no
  circular import (shelf_life only imports `services.categories`).
- Two new tests in `backend/tests/test_api.py`:
  `test_water_activity_is_derived_when_not_measured` and
  `test_product_accepts_wizard_measurements`.

Verified: `cd backend && python -m pytest -q` → **37 passed**.

Important contract to preserve in Task 3/4: `test_recommendations_fall_back_without_key`
asserts each tier still exposes `structure`, `otr_cc_m2_day` (> 0) and
`layers`. Keep those keys when the solver replaces the templates.

### Task 3 notes (for the next agent)

New file: `backend/services/stack_solver.py`.

- `solve_recommendations(product) -> {cost_optimized, sustainability_first,
  max_barrier}`. Same field names as the old templates (`structure`, `layers`,
  `otr_cc_m2_day`, `mvtr_g_m2_day`, `cost_per_1k`, `cost_per_unit`, `currency`,
  `carbon_kgco2e_per_kg`, `totalThicknessUm`, `tier`, `rationale`) **plus**:
  `meets_target`, `predicted_shelf_life_days`, `limiting_factor`,
  `target_shelf_life_days`, `recyclability_score`, `recyclability_grade`,
  `distinct_material_count`, `compostable`, `within_budget`, `why` (list).
- Search space: `OUTER_OPTIONS` x `BARRIER_OPTIONS` x `SEALANT_OPTIONS` = **1120
  candidates** (2-layer and 3-layer forms, never the same material twice).
- Evaluation reuses the shared engines only: `series_transmission`,
  `moisture_gain_curve`, `oxygen_accumulation`, `predict_shelf_life`,
  `stack_metrics`, `recyclability_score`. Comments explain that the quality ODE
  is integrated **once** (it is stack-independent) rather than per candidate —
  that is the whole reason a 1120-candidate search runs in ~0.12 s.
- Tiers: `cost_optimized` = cheapest feasible within budget (falls back to the
  feasible set, then to everything, if the budget excludes all of it);
  `sustainability_first` = best `recyclability_score`; `max_barrier` = lowest
  combined OTR/MVTR.
- When nothing is feasible, the closest stacks are returned with
  `meets_target: False` — the API must surface that, not hide it.

Measured behaviour (`backend/tests/test_stack_solver.py`, 10 tests):
- Chips (snacks, 35% fat, 180 d): 312/1120 candidates feasible. Every tier needs
  a real barrier core. `cost_optimized` = paperboard/met-PET/LDPE ~₹1006/1k;
  `max_barrier` = PET/alu-foil 9 µm/LDPE.
- Milk (dairy, 3.5% fat, 14 d): `cost_optimized` is a **2-layer** stack because
  a short chilled life needs no barrier core — i.e. the tiers genuinely respond
  to the product. `limiting_factor` is often `moisture` for chips and `none` for
  short-life chilled products.
- `test_solver_agrees_with_the_shelf_life_engine` cross-checks the solver's
  predicted shelf life against `digital_twin.build_shelf_life` for the same
  stack (must stay within 3 days and report the same limiting factor). **Keep
  that test passing** — it is what stops the recommendation screen and the
  simulator from contradicting each other.
- `max_barrier` is allowed to converge on the same stack for different products
  ("best barrier available" is product-independent). Do not "fix" that.

Verified: `cd backend && python -m pytest -q` → **47 passed**.

Not done yet: `routers/recommend.py` still calls `recommendations_for()` — the
API does **not** serve the solver output until Task 4.

### Task 4 notes (for the next agent)

`backend/routers/recommend.py` rewritten:
- `POST /recommendations/generate` now runs `solve_recommendations(product)`
  first and treats its output as the answer.
- `_merge_with_fallback()` is **gone**. It let the LLM overwrite numbers and
  could desync `structure` from `layers`. Replaced by `_guard_tiers()`, which
  only fills a required key if the solver somehow omitted it.
- The LLM is now constrained to prose: `_apply_llm_prose()` reads **only** the
  `rationale` string per tier and sets `rationale_source = "llm"`. Materials,
  thicknesses and all numbers stay as solved. `used_llm` is True only when at
  least one rationale was actually applied.
- `services/prompts.py`: `RECOMMEND_SYSTEM` rewritten to "explain, never invent"
  and `recommend_user_prompt(product, tiers=None)` now receives the solved
  stacks. The old prompt asked the model to generate numbers — that is the whole
  bug this task removes.
- `DISCLAIMER` updated (it no longer claims an AI estimate as the source of the
  numbers).

**LLM path is untested.** No `OPENAI_API_KEY` exists in this environment, so
`client.enabled` is always False and the `_apply_llm_prose` branch never runs.
It is written defensively (any malformed reply leaves the solver's rationale in
place and keeps `used_llm` False) but a future agent with a key should test it.

New test: `test_recommendations_are_solved_for_each_product` in
`backend/tests/test_api.py` — asserts the solver fields are exposed and that
chips and milk receive *different* structures and costs end-to-end.

Verified: `cd backend && python -m pytest -q` → **48 passed**.

## 5. Context the next agent needs

- Repo: Flutter app in `lib/`, FastAPI service in `backend/`. Commits
  auto-push to `main` via a `post-commit` hook.
- No Android device may be attached; `flutter analyze` + `flutter test` +
  `cd backend && python -m pytest` are the verification tools.
- A local web preview of the Flutter app can be served with
  `python -m http.server <port> --directory build/web` after
  `flutter build web --release`. Note: `flutter_inappwebview`'s **web**
  implementation loads the viewer in a `data:` iframe (opaque origin), so
  Dart→JS calls are silently dropped in a browser — the 3D mockup studio is
  view/rotate only there. Native Android/Windows works fully.
- The 3D mockup studio (`lib/widgets/packaging_mockup_studio.dart`) bundles
  `model-viewer` locally (`assets/model_viewer/model-viewer.min.js`) and is
  fully offline. Do not reintroduce a CDN dependency.
- Pre-existing `flutter analyze` warnings (unused import `sample_data.dart`,
  unused field `_selectedFormFactor`) live in
  `recommendation_result_screen.dart` and are expected to disappear in Task 5.
