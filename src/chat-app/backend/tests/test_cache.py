from unittest.mock import AsyncMock

import pytest

from app.schemas.device import DeviceState
from app.services.device_state import DeviceStateService


@pytest.mark.asyncio
async def test_cache_hit_within_ttl():
    upstream = AsyncMock()
    upstream.get_device_state = AsyncMock(
        return_value=DeviceState(device_id="device-1", fan=100)
    )
    service = DeviceStateService(upstream, redis_client=AsyncMock(), ttl_seconds=2)
    service.cache.get = AsyncMock(return_value={"device_id": "device-1", "fan": 100})

    first = await service.get_cached_device_state("device-1")
    second = await service.get_cached_device_state("device-1")

    assert first.fan == 100
    assert second.fan == 100
    assert upstream.get_device_state.await_count == 0


@pytest.mark.asyncio
async def test_cache_miss_after_ttl_fetches_fresh():
    upstream = AsyncMock()
    upstream.get_device_state = AsyncMock(
        side_effect=[
            DeviceState(device_id="device-1", fan=100),
            DeviceState(device_id="device-1", fan=200),
        ]
    )
    service = DeviceStateService(upstream, redis_client=AsyncMock(), ttl_seconds=1)
    service.cache.get = AsyncMock(side_effect=[None, None])
    service.cache.set = AsyncMock()

    first = await service.get_cached_device_state("device-1")
    second = await service.get_cached_device_state("device-1")

    assert first.fan == 100
    assert second.fan == 200
    assert upstream.get_device_state.await_count == 2
    assert service.cache.set.await_count == 2
