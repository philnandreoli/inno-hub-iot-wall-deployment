import logging
import time
from typing import Any, Optional

logger = logging.getLogger(__name__)


class TTLCache:
    def __init__(self, ttl_seconds: int = 15):
        self._store: dict[str, tuple[Any, float]] = {}
        self.ttl = ttl_seconds

    def get(self, key: str) -> Optional[Any]:
        if key in self._store:
            value, expires_at = self._store[key]
            if time.monotonic() < expires_at:
                logger.debug("Cache HIT for key: %s", key)
                return value
            del self._store[key]
            logger.debug("Cache EXPIRED for key: %s", key)
        logger.debug("Cache MISS for key: %s", key)
        return None

    def set(self, key: str, value: Any) -> None:
        self._store[key] = (value, time.monotonic() + self.ttl)
        logger.debug("Cache SET for key: %s, TTL: %ss", key, self.ttl)

    def invalidate(self, key: str) -> None:
        self._store.pop(key, None)

    def clear(self) -> None:
        self._store.clear()
