import pytest


@pytest.mark.asyncio
async def test_list_instances(async_client, override_instances_dependency, mock_instances_service):
    response = await async_client.get("/api/instances")
    assert response.status_code == 200
    body = response.json()
    assert "instances" in body
    assert len(body["instances"]) >= 1
    mock_instances_service.list_instances.assert_awaited_once()
