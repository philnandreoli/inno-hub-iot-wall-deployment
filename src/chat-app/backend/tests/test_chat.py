from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.schemas.device import DeviceState
from app.services.openai_service import OpenAIChatService


@pytest.mark.asyncio
async def test_chat_happy_path(async_client, override_openai_dependency, mock_openai_service):
    response = await async_client.post("/api/chat", json={"message": "hello"})
    assert response.status_code == 200
    body = response.json()
    assert body["reply"] == "hello"
    assert body["conversation_id"] == "conv-1"
    mock_openai_service.chat.assert_awaited_once()


@pytest.mark.asyncio
async def test_chat_conversation_continuity(
    async_client, override_openai_dependency, mock_openai_service
):
    mock_openai_service.chat = AsyncMock(side_effect=[("first", "conv-123"), ("second", "conv-123")])

    first = await async_client.post("/api/chat", json={"message": "msg1"})
    second = await async_client.post(
        "/api/chat",
        json={"message": "msg2", "conversation_id": first.json()["conversation_id"]},
    )

    assert first.status_code == 200
    assert second.status_code == 200
    assert first.json()["conversation_id"] == second.json()["conversation_id"] == "conv-123"


@pytest.mark.asyncio
async def test_tool_calling_path_queries_device_state():
    tool_call = SimpleNamespace(
        id="tool-1",
        function=SimpleNamespace(
            name="query_device_state", arguments='{"deviceId":"device-1"}'
        ),
        model_dump=lambda: {
            "id": "tool-1",
            "type": "function",
            "function": {"name": "query_device_state", "arguments": '{"deviceId":"device-1"}'},
        },
    )
    first_message = SimpleNamespace(content=None, tool_calls=[tool_call])
    second_message = SimpleNamespace(content="Device is online")

    completion_1 = SimpleNamespace(choices=[SimpleNamespace(message=first_message)])
    completion_2 = SimpleNamespace(choices=[SimpleNamespace(message=second_message)])

    service = OpenAIChatService.__new__(OpenAIChatService)
    service.client = SimpleNamespace(
        chat=SimpleNamespace(
            completions=SimpleNamespace(create=AsyncMock(side_effect=[completion_1, completion_2]))
        )
    )
    service.deployment = "test-model"
    service.conversations = {}
    service.device_state_service = SimpleNamespace(
        get_cached_device_state=AsyncMock(
            return_value=DeviceState(device_id="device-1", online=True, lamp=False, fan=0)
        )
    )

    reply, conversation_id = await service.chat("What's the device state?", "device-1")

    assert reply == "Device is online"
    assert conversation_id
    service.device_state_service.get_cached_device_state.assert_awaited_once_with("device-1")
