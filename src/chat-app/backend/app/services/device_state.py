import logging
from functools import lru_cache

from app.config import settings
from app.schemas.device import DeviceState
from app.services.cache import TTLCache
from app.services.eventhouse import EventHouseService

logger = logging.getLogger(__name__)


class DeviceStateService:
    def __init__(self, eventhouse_service: EventHouseService, ttl_seconds: int = 15):
        self.eventhouse_service = eventhouse_service
        self.cache = TTLCache(ttl_seconds=ttl_seconds)

    async def get_devices(self) -> list[str]:
        return await self.eventhouse_service.get_devices()

    async def get_cached_device_state(self, device_id: str) -> DeviceState:
        key = f"device_state:{device_id}"
        cached = self.cache.get(key)
        if cached is not None:
            return cached
        state = await self.eventhouse_service.get_device_state(device_id)
        self.cache.set(key, state)
        return state


@lru_cache(maxsize=1)
def get_device_state_service() -> DeviceStateService:
    ttl = max(5, min(30, settings.state_cache_ttl_seconds))
    logger.info("Initializing DeviceStateService with TTL=%ss", ttl)
    return DeviceStateService(EventHouseService(), ttl_seconds=ttl)
