"""Runtime configuration for the PackIT AI backend.

Everything is read from environment variables so the service runs with **zero
secrets** by default:

* ``STORAGE_BACKEND=memory`` (default) keeps data in-process — perfect for a
  hackathon demo / tests / CI.
* ``STORAGE_BACKEND=firestore`` switches to Firebase Firestore when
  ``GOOGLE_APPLICATION_CREDENTIALS`` (or ``FIRESTORE_PROJECT``) is present.
* If ``OPENAI_API_KEY`` is unset the LLM proxy degrades to deterministic
  rule-based fallbacks instead of failing — see ``services/llm_client.py``.
"""

from __future__ import annotations

import os
from functools import lru_cache


def _env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


class Settings:
    """Plain settings object (avoids a pydantic-settings dependency)."""

    def __init__(self) -> None:
        # ---- storage -------------------------------------------------------
        self.storage_backend: str = _env("STORAGE_BACKEND", "memory").lower()
        self.firestore_project: str = _env("FIRESTORE_PROJECT")
        self.google_application_credentials: str = _env(
            "GOOGLE_APPLICATION_CREDENTIALS"
        )
        self.seed_suppliers: bool = _env("SEED_SUPPLIERS", "true").lower() in {
            "1",
            "true",
            "yes",
        }

        # ---- LLM proxy -----------------------------------------------------
        # Any OpenAI-compatible endpoint works (OpenAI, Azure-style gateways,
        # OpenRouter, Groq, a local vLLM/Ollama server, ...).
        self.openai_api_key: str = _env("OPENAI_API_KEY")
        self.openai_base_url: str = _env(
            "OPENAI_BASE_URL", "https://api.openai.com/v1"
        ).rstrip("/")
        self.llm_model: str = _env("LLM_MODEL", "gpt-4o-mini")
        self.vision_model: str = _env("VISION_MODEL", self.llm_model)
        self.llm_timeout_seconds: float = float(_env("LLM_TIMEOUT_SECONDS", "60"))
        self.llm_max_tokens: int = int(_env("LLM_MAX_TOKENS", "1600"))

        # ---- app -----------------------------------------------------------
        self.require_auth: bool = _env("REQUIRE_AUTH", "false").lower() in {
            "1",
            "true",
            "yes",
        }
        self.cors_origins: list[str] = [
            o.strip()
            for o in _env("CORS_ORIGINS", "*").split(",")
            if o.strip()
        ] or ["*"]

    @property
    def llm_enabled(self) -> bool:
        return bool(self.openai_api_key)


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
