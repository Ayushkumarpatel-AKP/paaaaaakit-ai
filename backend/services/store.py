"""Pluggable document store.

* ``STORAGE_BACKEND=memory`` (default) — in-process dicts. Zero setup, used by
  tests and local demos.
* ``STORAGE_BACKEND=firestore`` — Firebase Firestore via ``google-cloud-firestore``
  (imported lazily, so the package is optional).

The interface mirrors the small slice of Firestore the app needs so routers
never care which backend is live.
"""

from __future__ import annotations

import threading
from typing import Any, Iterable, Protocol

from config import get_settings


class DocumentStore(Protocol):
    def put(self, collection: str, doc_id: str, data: dict) -> str: ...
    def get(self, collection: str, doc_id: str) -> dict | None: ...
    def update(self, collection: str, doc_id: str, patch: dict) -> dict | None: ...
    def list(
        self,
        collection: str,
        *,
        filters: dict[str, Any] | None = None,
        order_by: str | None = None,
        descending: bool = True,
        limit: int | None = None,
        search: str | None = None,
        search_fields: Iterable[str] | None = None,
    ) -> list[dict]: ...
    def delete(self, collection: str, doc_id: str) -> bool: ...


class MemoryStore:
    """Thread-safe in-memory document store."""

    def __init__(self) -> None:
        self._data: dict[str, dict[str, dict]] = {}
        self._lock = threading.RLock()

    def put(self, collection: str, doc_id: str, data: dict) -> str:
        with self._lock:
            bucket = self._data.setdefault(collection, {})
            record = dict(data)
            record["id"] = doc_id
            bucket[doc_id] = record
        return doc_id

    def get(self, collection: str, doc_id: str) -> dict | None:
        with self._lock:
            record = self._data.get(collection, {}).get(doc_id)
            return dict(record) if record else None

    def update(self, collection: str, doc_id: str, patch: dict) -> dict | None:
        with self._lock:
            bucket = self._data.get(collection, {})
            if doc_id not in bucket:
                return None
            bucket[doc_id].update(patch)
            return dict(bucket[doc_id])

    def list(
        self,
        collection: str,
        *,
        filters: dict[str, Any] | None = None,
        order_by: str | None = None,
        descending: bool = True,
        limit: int | None = None,
        search: str | None = None,
        search_fields: Iterable[str] | None = None,
    ) -> list[dict]:
        with self._lock:
            items = [dict(record) for record in self._data.get(collection, {}).values()]

        if filters:
            for key, value in filters.items():
                if value is None:
                    continue
                items = [item for item in items if item.get(key) == value]

        if search:
            needle = search.lower()
            fields = list(search_fields or items[0].keys() if items else [])
            needle_fields = [f for f in fields if f not in {"id", "imageUrl", "userId"}]
            items = [
                item
                for item in items
                if any(
                    needle in str(item.get(f, "")).lower() for f in needle_fields
                )
            ]

        if order_by:
            items.sort(key=lambda item: item.get(order_by) or "", reverse=descending)
        if limit is not None:
            items = items[:limit]
        return items

    def delete(self, collection: str, doc_id: str) -> bool:
        with self._lock:
            return self._data.get(collection, {}).pop(doc_id, None) is not None

    def count(self, collection: str) -> int:
        with self._lock:
            return len(self._data.get(collection, {}))


class FirestoreStore:
    """Firestore-backed store. Requires ``google-cloud-firestore`` + credentials."""

    def __init__(self, project: str | None = None) -> None:
        try:
            from google.cloud import firestore  # type: ignore
        except ImportError as exc:  # pragma: no cover - optional dependency
            raise RuntimeError(
                "STORAGE_BACKEND=firestore requires google-cloud-firestore. "
                "Install it or use STORAGE_BACKEND=memory."
            ) from exc
        self._firestore = firestore
        self._client = firestore.Client(project=project or None)

    def _collection(self, name: str):
        return self._client.collection(name)

    def put(self, collection: str, doc_id: str, data: dict) -> str:
        self._collection(collection).document(doc_id).set(dict(data))
        return doc_id

    def get(self, collection: str, doc_id: str) -> dict | None:
        snapshot = self._collection(collection).document(doc_id).get()
        if not snapshot.exists:
            return None
        record = snapshot.to_dict() or {}
        record["id"] = doc_id
        return record

    def update(self, collection: str, doc_id: str, patch: dict) -> dict | None:
        ref = self._collection(collection).document(doc_id)
        if not ref.get().exists:
            return None
        ref.update(dict(patch))
        return self.get(collection, doc_id)

    def list(
        self,
        collection: str,
        *,
        filters: dict[str, Any] | None = None,
        order_by: str | None = None,
        descending: bool = True,
        limit: int | None = None,
        search: str | None = None,
        search_fields: Iterable[str] | None = None,
    ) -> list[dict]:
        from google.cloud.firestore_v1.base_query import FieldFilter  # type: ignore

        query = self._collection(collection)
        for key, value in (filters or {}).items():
            if value is not None:
                query = query.where(filter=FieldFilter(key, "==", value))
        if order_by:
            direction = (
                self._firestore.Query.DESCENDING
                if descending
                else self._firestore.Query.ASCENDING
            )
            query = query.order_by(order_by, direction=direction)
        if limit is not None:
            query = query.limit(limit)

        items: list[dict] = []
        for doc in query.stream():
            record = doc.to_dict() or {}
            record["id"] = doc.id
            items.append(record)

        if search:
            needle = search.lower()
            fields = list(search_fields or [])
            items = [
                item
                for item in items
                if any(needle in str(item.get(f, "")).lower() for f in fields)
            ]
        return items

    def delete(self, collection: str, doc_id: str) -> bool:
        self._collection(collection).document(doc_id).delete()
        return True


_store: DocumentStore | None = None


def get_store() -> DocumentStore:
    global _store
    if _store is None:
        settings = get_settings()
        if settings.storage_backend == "firestore":
            _store = FirestoreStore(settings.firestore_project)
        else:
            _store = MemoryStore()
    return _store


def reset_store() -> None:
    """Test helper — drop the cached store instance."""
    global _store
    _store = None
