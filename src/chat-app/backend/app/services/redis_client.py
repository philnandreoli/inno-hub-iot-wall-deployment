import logging
from functools import lru_cache

import redis.asyncio as aioredis

from app.config import settings

logger = logging.getLogger(__name__)


@lru_cache(maxsize=1)
def get_redis_client() -> aioredis.Redis:
    client = aioredis.from_url(
        settings.redis_url,
        decode_responses=True,
        socket_connect_timeout=5,
        socket_timeout=5,
    )
    logger.info("Redis client created: %s", settings.redis_url)
    return client
