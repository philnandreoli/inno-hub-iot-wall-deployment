import pytest


@pytest.mark.asyncio
async def test_lamp_command(async_client, override_eventgrid_dependency, mock_eventgrid_service):
    response = await async_client.post(
        "/api/commands/device-1",
        json={"action": "lamp", "value": True},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["success"] is True
    mock_eventgrid_service.publish_command.assert_awaited_once_with("device-1", "lamp", True)


@pytest.mark.asyncio
async def test_fan_command(async_client, override_eventgrid_dependency, mock_eventgrid_service):
    response = await async_client.post(
        "/api/commands/device-1",
        json={"action": "fan", "value": 1200},
    )
    assert response.status_code == 200
    mock_eventgrid_service.publish_command.assert_awaited_once_with("device-1", "fan", 1200)


@pytest.mark.asyncio
async def test_invalid_action_rejected(async_client, override_eventgrid_dependency):
    response = await async_client.post(
        "/api/commands/device-1",
        json={"action": "invalid", "value": True},
    )
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_invalid_fan_value_rejected(async_client, override_eventgrid_dependency):
    response = await async_client.post(
        "/api/commands/device-1",
        json={"action": "fan", "value": 50000},
    )
    assert response.status_code == 422
