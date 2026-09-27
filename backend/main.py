"""PackIT AI backend — FastAPI application entrypoint.

Run locally::

    cd backend
    uvicorn main:app --reload --port 8000

Runs with zero secrets: data lives in memory and the LLM endpoints degrade to
deterministic fallbacks. See ``config.py`` for the env switches.
"""

from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from config import get_settings
from data.seed_suppliers import seed_suppliers
from routers import (
    audit,
    chat,
    dashboard,
    history,
    layerstack,
    lca,
    products,
    recommend,
    reports,
    simulate,
    suppliers,
)
from services.llm_client import LLMClient
from services.store import get_store

settings = get_settings()


@asynccontextmanager
async def lifespan(_app: FastAPI):
    if settings.seed_suppliers:
        seed_suppliers(get_store())
    yield


app = FastAPI(
    title="PackIT AI Backend",
    version="1.0.0",
    description=(
        "Packaging digital twin, shelf-life, LCA, auditor, recommendations and "
        "chat — real physics where it matters, LLM-assisted where it helps."
    ),
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials="*" not in settings.cors_origins,
    allow_methods=["*"],
    allow_headers=["*"],
)

for module in (
    products,
    simulate,
    recommend,
    audit,
    layerstack,
    lca,
    suppliers,
    chat,
    dashboard,
    history,
    reports,
):
    app.include_router(module.router)


@app.get("/health", tags=["meta"])
def health() -> dict:
    """Liveness + configuration probe (the splash screen pings this)."""
    store = get_store()
    llm = LLMClient()
    try:
        storage_ok = store.list("suppliers", limit=1) is not None
        storage_error = None
    except Exception as exc:  # pragma: no cover - defensive
        storage_ok = False
        storage_error = str(exc)

    return {
        "status": "ok" if storage_ok else "degraded",
        "version": app.version,
        "checks": {
            "storage": {
                "backend": settings.storage_backend,
                "reachable": storage_ok,
                "error": storage_error,
            },
            "llm": {**llm.health(), "reachable": None},
        },
    }


@app.get("/", tags=["meta"])
def root() -> dict:
    return {
        "name": "PackIT AI backend",
        "docs": "/docs",
        "health": "/health",
    }
