"""LLM proxy.

Keys live **only** here — the Flutter app never talks to an LLM provider
directly. Any OpenAI-compatible endpoint works (OpenAI, a gateway, Groq,
OpenRouter, local vLLM/Ollama) via ``OPENAI_BASE_URL``.

If ``OPENAI_API_KEY`` is unset, :meth:`LLMClient.complete` raises
:class:`LLMUnavailable` and routers fall back to deterministic rule-based
answers (see ``services/fallback.py``). That keeps every endpoint working with
zero secrets.
"""

from __future__ import annotations

import base64
import json
from dataclasses import dataclass

import httpx

from config import Settings, get_settings


class LLMUnavailable(RuntimeError):
    """Raised when no LLM key is configured or the provider call fails."""


@dataclass
class LLMResult:
    text: str
    used_llm: bool
    model: str
    error: str | None = None


def parse_json(text: str) -> dict:
    """Best-effort JSON extraction from an LLM reply.

    Strips markdown fences and trailing prose, then parses the outermost object.
    """
    if not text:
        raise ValueError("empty LLM response")
    cleaned = text.strip()
    if cleaned.startswith("```"):
        cleaned = cleaned.split("```", 2)[1] if cleaned.count("```") >= 2 else cleaned
        cleaned = cleaned.split("\n", 1)[-1] if cleaned.lower().startswith(("json", "python")) else cleaned
    start = cleaned.find("{")
    end = cleaned.rfind("}")
    if start == -1 or end == -1 or end <= start:
        raise ValueError("no JSON object found in LLM response")
    return json.loads(cleaned[start : end + 1])


class LLMClient:
    def __init__(self, settings: Settings | None = None) -> None:
        self.settings = settings or get_settings()

    @property
    def enabled(self) -> bool:
        return self.settings.llm_enabled

    def _headers(self) -> dict[str, str]:
        return {
            "Authorization": f"Bearer {self.settings.openai_api_key}",
            "Content-Type": "application/json",
        }

    def _request(self, payload: dict) -> str:
        if not self.enabled:
            raise LLMUnavailable("OPENAI_API_KEY is not configured")
        url = f"{self.settings.openai_base_url}/chat/completions"
        try:
            response = httpx.post(
                url,
                headers=self._headers(),
                json=payload,
                timeout=self.settings.llm_timeout_seconds,
            )
            response.raise_for_status()
        except httpx.HTTPError as exc:  # network / provider errors
            raise LLMUnavailable(f"LLM request failed: {exc}") from exc

        data = response.json()
        try:
            return data["choices"][0]["message"]["content"] or ""
        except (KeyError, IndexError, TypeError) as exc:
            raise LLMUnavailable(f"unexpected LLM response shape: {data}") from exc

    def complete(
        self,
        *,
        system: str,
        messages: list[dict],
        json_mode: bool = False,
        model: str | None = None,
    ) -> str:
        """Text completion. ``messages`` are ``{"role","content"}`` dicts."""
        payload: dict = {
            "model": model or self.settings.llm_model,
            "messages": [{"role": "system", "content": system}, *messages],
            "max_tokens": self.settings.llm_max_tokens,
            "temperature": 0.2,
        }
        if json_mode:
            payload["response_format"] = {"type": "json_object"}
        return self._request(payload)

    def vision(
        self,
        *,
        image_bytes: bytes,
        mime_type: str,
        prompt: str,
        model: str | None = None,
        json_mode: bool = True,
    ) -> str:
        """Vision completion for the packaging auditor."""
        b64 = base64.b64encode(image_bytes).decode("ascii")
        payload: dict = {
            "model": model or self.settings.vision_model,
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt},
                        {
                            "type": "image_url",
                            "image_url": {"url": f"data:{mime_type};base64,{b64}"},
                        },
                    ],
                }
            ],
            "max_tokens": self.settings.llm_max_tokens,
            "temperature": 0.1,
        }
        if json_mode:
            payload["response_format"] = {"type": "json_object"}
        return self._request(payload)

    def health(self) -> dict:
        return {
            "configured": self.enabled,
            "baseUrl": self.settings.openai_base_url,
            "textModel": self.settings.llm_model,
            "visionModel": self.settings.vision_model,
        }
