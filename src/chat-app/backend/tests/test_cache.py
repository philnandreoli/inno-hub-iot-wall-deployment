import asyncio
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
    service = DeviceStateService(upstream, ttl_seconds=2)

    await service.get_cached_device_state("device-1")
    await service.get_cached_device_state("device-1")

    assert upstream.get_device_state.await_count == 1


@pytest.mark.asyncio
async def test_cache_miss_after_ttl_fetches_fresh():
    upstream = AsyncMock()
    upstream.get_device_state = AsyncMock(
        side_effect=[
            DeviceState(device_id="device-1", fan=100),
            DeviceState(device_id="device-1", fan=200),
        ]
    )
    service = DeviceStateService(upstream, ttl_seconds=1)

    first = await service.get_cached_device_state("device-1")
    await asyncio.sleep(1.1)
    second = await service.get_cached_device_state("device-1")

    assert first.fan == 100
    assert second.fan == 200
    assert upstream.get_device_state.await_count == 2
