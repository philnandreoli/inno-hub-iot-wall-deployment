from collections.abc import AsyncGenerator
from unittest.mock import AsyncMock, Mock

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.main import app
from app.schemas.device import DeviceState
from app.schemas.instance import AioInstance
from app.services.device_state import get_device_state_service
from app.services.eventgrid_service import get_eventgrid_service
from app.services.instances_service import get_instances_service
from app.services.openai_service import get_openai_service


@pytest_asyncio.fixture
async def async_client() -> AsyncGenerator[AsyncClient, None]:
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client


@pytest.fixture
def mock_openai_service() -> Mock:
    return Mock(chat=AsyncMock(return_value=("hello", "conv-1")))


@pytest.fixture
def mock_device_state_service() -> Mock:
    service = Mock()
    service.get_devices = AsyncMock(return_value=["device-1", "device-2"])
    service.get_cached_device_state = AsyncMock(
        return_value=DeviceState(
            device_id="device-1",
            online=True,
            lamp=False,
            fan=0,
            temperature=24.5,
            vibration=0.1,
            error_code=None,
            last_updated="2024-01-01T00:00:00Z",
            raw={"deviceId": "device-1"},
        )
    )
    return service


@pytest.fixture
def mock_eventgrid_service() -> Mock:
    service = Mock()
    service.publish_command = AsyncMock(return_value=True)
    return service


@pytest.fixture
def mock_instances_service() -> Mock:
    service = Mock()
    service.list_instances = AsyncMock(
        return_value=[
            AioInstance(
                name="my-instance",
                resource_group="rg-1",
                subscription_id="sub-1",
                location="eastus",
                description="test instance",
            )
        ]
    )
    return service


@pytest.fixture
def override_openai_dependency(mock_openai_service: Mock) -> AsyncGenerator[None, None]:
    app.dependency_overrides[get_openai_service] = lambda: mock_openai_service
    yield
    app.dependency_overrides.pop(get_openai_service, None)


@pytest.fixture
def override_device_state_dependency(
    mock_device_state_service: Mock,
) -> AsyncGenerator[None, None]:
    app.dependency_overrides[get_device_state_service] = lambda: mock_device_state_service
    yield
    app.dependency_overrides.pop(get_device_state_service, None)


@pytest.fixture
def override_eventgrid_dependency(mock_eventgrid_service: Mock) -> AsyncGenerator[None, None]:
    app.dependency_overrides[get_eventgrid_service] = lambda: mock_eventgrid_service
    yield
    app.dependency_overrides.pop(get_eventgrid_service, None)


@pytest.fixture
def override_instances_dependency(mock_instances_service: Mock) -> AsyncGenerator[None, None]:
    app.dependency_overrides[get_instances_service] = lambda: mock_instances_service
    yield
    app.dependency_overrides.pop(get_instances_service, None)
