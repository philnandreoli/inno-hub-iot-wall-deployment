import logging
from functools import lru_cache

from app.config import settings
from app.schemas.device import DeviceState
from app.services.cache import RedisCache
from app.services.eventhouse import EventHouseService
from app.services.redis_client import get_redis_client

logger = logging.getLogger(__name__)


class DeviceStateService:
    def __init__(
        self, eventhouse_service: EventHouseService, redis_client, ttl_seconds: int = 15
    ):
        self.eventhouse_service = eventhouse_service
        self.cache = RedisCache(redis_client, ttl_seconds=ttl_seconds, key_prefix="device_state")

    async def get_devices(self) -> list[str]:
        return await self.eventhouse_service.get_devices()

    async def get_cached_device_state(self, device_id: str) -> DeviceState:
        cached_dict = await self.cache.get(device_id)
        if cached_dict is not None:
            return DeviceState(**cached_dict)
        state = await self.eventhouse_service.get_device_state(device_id)
        await self.cache.set(device_id, state.model_dump(exclude={"raw"}))
        return state


@lru_cache(maxsize=1)
def get_device_state_service() -> DeviceStateService:
    ttl = max(5, min(30, settings.state_cache_ttl_seconds))
    logger.info("Initializing DeviceStateService with Redis TTL=%ss", ttl)
    return DeviceStateService(
        EventHouseService(),
        redis_client=get_redis_client(),
        ttl_seconds=ttl,
    )
