from unittest.mock import AsyncMock

import pytest

from app.schemas.device import DeviceState
from app.services.cache import TTLCache
from app.services.device_state import DeviceStateService


@pytest.mark.asyncio
async def test_get_devices(async_client, override_device_state_dependency):
    response = await async_client.get("/api/devices")
    assert response.status_code == 200
    assert response.json() == {"devices": ["device-1", "device-2"]}


@pytest.mark.asyncio
async def test_get_device_state(async_client, override_device_state_dependency):
    response = await async_client.get("/api/device-state/device-1")
    assert response.status_code == 200
    body = response.json()
    assert body["device_id"] == "device-1"


@pytest.mark.asyncio
async def test_cache_hit_uses_cached_result():
    upstream = AsyncMock()
    upstream.get_device_state = AsyncMock(
        return_value=DeviceState(device_id="device-1", online=True)
    )
    service = DeviceStateService(upstream, redis_client=AsyncMock(), ttl_seconds=15)
    service.cache.get = AsyncMock(return_value={"device_id": "device-1", "online": True})
    service.cache.set = AsyncMock()

    first = await service.get_cached_device_state("device-1")
    second = await service.get_cached_device_state("device-1")

    assert first.device_id == "device-1"
    assert second.device_id == "device-1"
    assert upstream.get_device_state.await_count == 0


def test_ttlcache_basic_behavior():
    cache = TTLCache(ttl_seconds=1)
    cache.set("k", "v")
    assert cache.get("k") == "v"
