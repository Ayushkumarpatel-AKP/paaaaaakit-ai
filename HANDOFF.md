# HANDOFF — Make AI packaging recommendations genuinely product-specific

> **For the next agent:** this file is the single source of truth for an
> in-progress task. Read it fully before touching code. Update the
> **STATUS** table after every task and commit that update together with the
> task's code. Commits are auto-pushed by `.githooks/post-commit`.

Last updated: task 6 complete — **all planned tasks are done.**

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
| 5 | Flutter: real values on result screen | **DONE** | (this commit) |
| 6 | Verify + document | **DONE** | (this commit) |

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

### Task 5 notes (for the next agent)

`lib/screens/recommendation_result_screen.dart`:
- **Tier→card mapping fixed.** Card 1 (the default-selected, formerly
  "Recommended (MET)") now receives `max_barrier`; card 2 receives
  `sustainability_first`. Previously card 1 was filled with the compostable
  stack while labelled as metallised PET.
- `_applyTier()` now writes solver-derived values over the literals:
  `meetsTarget`, `withinBudget`, `isRecommended`, `badge` ('Meets target' /
  'Below target'), `badgeColor`, `shelfLife`, `lifeDetail`, `limitingFactor`,
  `recyclability`, `why`, `rationale`.
- The hardcoded **'95% MATCH'** chip and the `'... (${matchScore}%)'` badge are
  gone; both now render the tier's real status. `matchScore` and `protection`
  are no longer displayed anywhere (`sealability` and `mechanical` spec rows
  were removed outright — the backend never computed them).
- New spec rows: **Limiting Factor**, **Recyclability**, and a
  **Predicted Shelf Life vs target** row. New `_buildReasonsCard()` renders the
  solver's `why` list plus the rationale, so the reasoning is visible.
- Helpers added: `_formatDays()`, `_prettyFactor()`, `_buildReasonsCard()`.
- **Deleted the dead "AI analysis" block**: `_analyzeProduct()`,
  `_calculateConfidence()` (the fake 70-90 score) and `_generateRationale()`,
  plus the `_analysisResult` map and the unused `_selectedFormFactor` field. It
  was verified to be genuinely dead — `_analysisResult` was written but never
  read by any widget, so the fake confidence score was never even shown. That
  also removed the two pre-existing analyzer warnings and the unused
  `sample_data.dart` import.

**Offline fallback preserved:** when the backend is unreachable `_applyTier()`
never runs and the bundled sample card is shown. The new spec rows therefore use
`?? '—'` / `?? activeOption['shelfLife']` so they do not render "null".

Verified: `flutter analyze` → **No issues found!** (the 2 legacy warnings are
gone), `flutter test` → 2 passed.

Not yet done: Task 6 (final cross-check + docs). The APK at the repo root is
still the pre-Task-1 build — see "Optional / later".

### Task 6 notes — final verification

All green:
- `cd backend && python -m pytest -q` → **48 passed**
- `flutter analyze` → **No issues found!** (the 2 legacy warnings are gone)
- `flutter test` → 2 passed

End-to-end smoke (real `TestClient` against `POST /products` +
`POST /recommendations/generate`), showing the tiers now track the product:

| Product | tier | life vs target | limited by | ₹/1k | stack |
|---|---|---|---|---|---|
| Potato Chips (35% fat, 180 d, aw 0.29) | cost | 185 / 180 | moisture | 1006 | Paperboard / Met-PET 15 / LDPE 40 |
| Potato Chips | max barrier | 221 / 180 | quality | 1181 | PET 12 / Alu-foil 9 / LDPE 40 |
| Pasteurized Milk (3.5% fat, 14 d, aw 0.97) | cost | 30 / 14 | none | 687 | Paperboard / LDPE 40 **(no barrier core)** |
| Biscuits (22% fat, 120 d, aw 0.32) | cost | 145 / 120 | quality | 687 | Paperboard / LDPE 40 |

Every tier reports `within_budget: true` against the wizard's real budget
(₹1000-5000 per 1k units). Before this work every product returned the same
three templates and the budget was ignored entirely.

---

## 6. Known limitations — be honest about these, do not paper over them

1. **`limiting_factor: "none"` means "nothing failed inside the test window",
   not "it will last forever".** For short-life chilled products (milk) the
   window closes before any threshold is crossed. The UI renders this as
   "Nothing failed in the test window".
2. **The milk result is optimistic for real dairy.** The model has no light
   barrier, no headspace-oxygen/pasteurisation term and no package-integrity
   term, so it concludes a paperboard/LDPE pouch holds pasteurised milk for 14
   days at 5 °C. Treat that tier as "cheapest stack the model cannot fault",
   not as a validated dairy pack.
3. **`waterActivity` is estimated** (Task 2) from category + moisture unless the
   client measures it. Add an Aw field to the wizard when a real value becomes
   available.
4. **`recyclability_score` is the shared LCA engine's mass-weighted number.**
   Heavy, low-impact layers can make a 3-material laminate look greener than it
   is in practice. The solver exposes `distinct_material_count` and
   `compostable` so the UI can add nuance; it deliberately does not fork the LCA
   scoring, because the LCA screen must agree.
5. **The search grid is a design choice, not a truth.** `OUTER_OPTIONS`,
   `BARRIER_OPTIONS`, `SEALANT_OPTIONS` bound what can be recommended. Widen
   them to widen the answers.
6. **The LLM path is untested** (no key in this environment) — see Task 4 notes.
7. **Sensitivity flags** (`oxygenSensitivity`, `lightSensitivity`) are derived in
   the Flutter client but the solver does not consume them yet. They are stored
   and shown; wiring them into the barrier requirement would be a genuine next
   improvement.

## 7. Suggested next work

1. Rebuild + commit the APK (see "Optional / later") so the shipped build has
   all of this.
2. Feed `oxygenSensitivity` / `lightSensitivity` and `ph` into the solver's
   requirement step (light barrier for photo-oxidation, acid-resistant sealant
   for pH < 4.6).
3. Add a light-barrier material (e.g. pigmented/metallised film without foil) to
   `material_db` so `max_barrier` is not forced to aluminium for dairy.
4. Show `required_mvtr` / `required_otr` explicitly — the solver computes a
   feasible set but does not currently report the threshold it was solving for.
5. Surface the `why` list in the PDF report (`services/projects.py` builds it).

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
