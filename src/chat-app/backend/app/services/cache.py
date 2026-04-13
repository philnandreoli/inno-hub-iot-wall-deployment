import json
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


class RedisCache:
    """Redis-backed cache with TTL. Falls back gracefully if Redis is unavailable."""

    def __init__(self, redis_client, ttl_seconds: int = 15, key_prefix: str = "cache"):
        self._redis = redis_client
        self.ttl = ttl_seconds
        self._prefix = key_prefix

    def _key(self, key: str) -> str:
        return f"{self._prefix}:{key}"

    async def get(self, key: str):
        try:
            raw = await self._redis.get(self._key(key))
            if raw is not None:
                logger.debug("Redis cache HIT: %s", key)
                return json.loads(raw)
            logger.debug("Redis cache MISS: %s", key)
            return None
        except Exception as exc:
            logger.warning("Redis GET error (falling back to None): %s", exc)
            return None

    async def set(self, key: str, value) -> None:
        try:
            await self._redis.set(self._key(key), json.dumps(value), ex=self.ttl)
            logger.debug("Redis cache SET: %s TTL=%ss", key, self.ttl)
        except Exception as exc:
            logger.warning("Redis SET error (skipping cache): %s", exc)

    async def invalidate(self, key: str) -> None:
        try:
            await self._redis.delete(self._key(key))
        except Exception as exc:
            logger.warning("Redis DELETE error: %s", exc)
