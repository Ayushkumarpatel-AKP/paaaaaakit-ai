# 📦 PackIT AI — Smart Packaging & Digital Twin Engineering

**PackIT AI** is a Deep-Tech AI & Physics-Powered Smart Packaging Simulator designed for food and pharmaceutical packaging engineers. It features 3D layer customizers, real-time Arrhenius chemical reaction & Fickian moisture diffusion digital twins, multi-modal vision packaging auditing, and AI recommendation engines.

---

## 📥 Direct Android APK Download

A pre-built release APK is committed at the repo root — no build tools needed.

| | |
|---|---|
| **File** | [`PackIT_AI_v1.0.apk`](https://github.com/Ayushkumarpatel-AKP/paaaaaakit-ai/raw/main/PackIT_AI_v1.0.apk) |
| **Size** | ~47.8 MB |
| **Built** | 27 Sep 2026 · `flutter build apk --release` (Flutter 3.35.3) |

[![Download PackIT AI APK](https://img.shields.io/badge/Download-PackIT__AI__v1.0.apk-00F2FE?style=for-the-badge&logo=android&logoColor=white)](https://github.com/Ayushkumarpatel-AKP/paaaaaakit-ai/raw/main/PackIT_AI_v1.0.apk)

### 📲 How to Install on Android:
1. Tap the **Download** button above, or grab [`PackIT_AI_v1.0.apk`](https://github.com/Ayushkumarpatel-AKP/paaaaaakit-ai/raw/main/PackIT_AI_v1.0.apk) straight from the [Releases page](https://github.com/Ayushkumarpatel-AKP/paaaaaakit-ai/releases).
2. Open the downloaded file on your Android phone.
3. If prompted, enable **"Install from unknown sources"** for your browser/file manager.
4. Tap **Install** and open **PackIT AI**!

> Upgrading over an older install? Uninstall first — the release APK is signed with the
> debug key here, so signature mismatch will block an in-place update.

---

## 🔥 Key Features

- **⚡ Digital Twin Simulator**: Live Arrhenius ODE kinetics ($k = A \cdot e^{-E_a/RT}$) & Fickian diffusion equations under variable chamber presets (*Standard, Tropical, Cold Chain, Arid*).
- **📷 AI Packaging Auditor**: Vision inspection to detect layer stacks, micro-pinholes, seal degradation, and FDA contact compliance.
- **🛡️ 3-Tier AI Recommendation Engine**: Instant generation of *Cost-Optimized*, *Sustainability-First*, and *Maximum-Barrier* packaging structures.
- **🎨 3D Layer Stack Customizer**: Dynamic barrier permeability recalculation (OTR/MVTR) using series permeability equations.
- **🤖 Context-Aware AI Chat Assistant**: RAG-powered assistant for polymer science, TAPPI standards, and food preservation physics.

---

## 🛠️ Tech Stack

- **Frontend**: Flutter (Dart), Google Fonts (Inter), FlChart, Custom 3D Viewers
- **Backend**: FastAPI (Python) — Arrhenius kinetics via `scipy.integrate.solve_ivp`,
  series permeability, shelf-life models, LCA, LLM proxy (recommendations, chat, vision audit)
- **Target Platforms**: Android (ARM64, ARMv7, x86_64), Web, Windows Desktop
- **License**: MIT

---

## ⚙️ Running the full stack

The Flutter app talks to the FastAPI backend in [`backend/`](backend/). It runs with
**zero secrets** — data lives in memory and the AI endpoints fall back to
deterministic, material-database-grounded answers when no LLM key is set.

```bash
# 1. Start the backend
cd backend
python -m pip install -r requirements.txt
uvicorn main:app --reload --port 8000      # docs at http://localhost:8000/docs

# 2. Run the app against it (from the repo root)
flutter run --dart-define=API_BASE_URL=http://localhost:8000
```

Notes:
- Android emulators reach the host via `10.0.2.2` (already the default on Android).
- Without the backend the app still runs on its bundled sample data and shows an
  *offline / sample data* badge instead of pretending.
- Enable the LLM proxy with `OPENAI_API_KEY` (+ optional `OPENAI_BASE_URL`,
  `LLM_MODEL`, `VISION_MODEL`). CPU-only demos: leave it unset.
- Firebase is supported via `STORAGE_BACKEND=firestore`; the default `memory`
  backend needs no credentials.

See [`backend/README.md`](backend/README.md) for the endpoint list and the honesty
notes on what is real physics vs AI-assisted guidance.
