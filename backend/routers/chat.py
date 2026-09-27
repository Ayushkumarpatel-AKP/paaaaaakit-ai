"""Context-aware AI chat assistant.

The backend injects live session context (product spec + latest simulation)
into the system prompt before calling the LLM. Without a key it answers from
the deterministic rule-based responder so the screen still works.
"""

from __future__ import annotations

from fastapi import APIRouter, HTTPException

from models.schemas import ChatRequest
from services.common import new_id, now_iso
from services.fallback import chat_answer
from services.llm_client import LLMClient, LLMUnavailable
from services.prompts import chat_system_prompt
from services.store import get_store

router = APIRouter(prefix="/chat", tags=["chat"])

COLLECTION = "chat_messages"


def _build_context(product: dict | None, simulation: dict | None) -> dict:
    context: dict = {
        "category": (product or {}).get("category") or "n/a",
        "targetShelfLifeDays": (product or {}).get("targetShelfLifeDays") or "n/a",
        "packagingFormat": (product or {}).get("packagingFormat") or "n/a",
        "lastDay": "n/a",
        "lastQuality": "n/a",
        "lastMoisture": "n/a",
    }
    if simulation:
        series = simulation.get("resultTimeSeries") or {}
        times = series.get("time") or []
        quality = series.get("quality") or []
        moisture = series.get("moistureGain") or []
        if times:
            context["lastDay"] = times[-1]
        if quality:
            context["lastQuality"] = round(quality[-1], 1)
        if moisture:
            context["lastMoisture"] = round(moisture[-1], 4)
    return context


@router.post("/message")
def send_message(payload: ChatRequest) -> dict:
    store = get_store()
    product = store.get("products", payload.productId) if payload.productId else None

    simulation = None
    if payload.simId:
        simulation = store.get("simulations", payload.simId)
    elif payload.productId:
        recent = store.list(
            "simulations",
            filters={"productId": payload.productId},
            order_by="createdAt",
            limit=1,
        )
        simulation = recent[0] if recent else None

    context = _build_context(product, simulation)
    history = store.list(
        COLLECTION,
        filters={"sessionId": payload.sessionId},
        order_by="timestamp",
        descending=False,
        limit=20,
    )

    used_llm = False
    client = LLMClient()
    if client.enabled:
        try:
            messages = [
                {"role": turn["role"], "content": turn["content"]}
                for turn in history
                if turn.get("role") in {"user", "assistant"}
            ]
            messages.append({"role": "user", "content": payload.message})
            answer = client.complete(
                system=chat_system_prompt(context), messages=messages
            )
            used_llm = True
        except LLMUnavailable:
            answer = chat_answer(context, payload.message)
    else:
        answer = chat_answer(context, payload.message)

    user_turn = {
        "id": new_id("msg"),
        "sessionId": payload.sessionId,
        "role": "user",
        "content": payload.message,
        "timestamp": now_iso(),
    }
    assistant_turn = {
        "id": new_id("msg"),
        "sessionId": payload.sessionId,
        "role": "assistant",
        "content": answer,
        "used_llm": used_llm,
        "timestamp": now_iso(),
    }
    store.put(COLLECTION, user_turn["id"], user_turn)
    store.put(COLLECTION, assistant_turn["id"], assistant_turn)

    return {
        "sessionId": payload.sessionId,
        "role": "assistant",
        "content": answer,
        "used_llm": used_llm,
        "timestamp": assistant_turn["timestamp"],
        "context": context,
    }


@router.get("/{session_id}/messages")
def messages(session_id: str, limit: int = 100) -> list[dict]:
    if not session_id:
        raise HTTPException(status_code=400, detail="sessionId required")
    return get_store().list(
        COLLECTION,
        filters={"sessionId": session_id},
        order_by="timestamp",
        descending=False,
        limit=limit,
    )
