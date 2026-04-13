import json
import logging
from functools import lru_cache
from typing import Any, Optional
from uuid import uuid4

from azure.identity import get_bearer_token_provider
from openai import AsyncAzureOpenAI

from app.config import settings
from app.services.auth import get_credential
from app.services.device_state import DeviceStateService, get_device_state_service

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = (
    "You are an IoT operations assistant. You help operators understand current device operational "
    "state and issue device commands. When asked about device state, use the query_device_state "
    "tool to fetch live data. Be concise, factual, and safety-conscious."
)

TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "query_device_state",
            "description": "Retrieve the current operational state of a device from EventHouse",
            "parameters": {
                "type": "object",
                "properties": {
                    "deviceId": {
                        "type": "string",
                        "description": "The device identifier to query",
                    }
                },
                "required": ["deviceId"],
            },
        },
    }
]


class OpenAIChatService:
    def __init__(self, device_state_service: DeviceStateService):
        if not settings.azure_openai_endpoint:
            raise ValueError("AZURE_OPENAI_ENDPOINT is not configured")
        token_provider = get_bearer_token_provider(
            get_credential(), "https://cognitiveservices.azure.com/.default"
        )
        self.client = AsyncAzureOpenAI(
            azure_endpoint=settings.azure_openai_endpoint,
            azure_deployment=settings.azure_openai_deployment,
            azure_ad_token_provider=token_provider,
            api_version="2024-05-01-preview",
        )
        self.deployment = settings.azure_openai_deployment
        self.device_state_service = device_state_service
        self.conversations: dict[str, list[dict[str, Any]]] = {}

    async def chat(
        self,
        message: str,
        device_id: Optional[str] = None,
        conversation_id: Optional[str] = None,
    ) -> tuple[str, str]:
        conv_id = conversation_id or str(uuid4())
        history = self.conversations.setdefault(
            conv_id, [{"role": "system", "content": SYSTEM_PROMPT}]
        )
        user_content = message
        if device_id:
            user_content = f"Device context: {device_id}\nUser message: {message}"
        history.append({"role": "user", "content": user_content})

        first = await self.client.chat.completions.create(
            model=self.deployment,
            messages=history,
            tools=TOOLS,
            tool_choice="auto",
        )
        first_message = first.choices[0].message

        if getattr(first_message, "tool_calls", None):
            tool_messages = await self._handle_tool_calls(first_message.tool_calls)
            history.append(
                {
                    "role": "assistant",
                    "content": first_message.content or "",
                    "tool_calls": [tool.model_dump() for tool in first_message.tool_calls],
                }
            )
            history.extend(tool_messages)
            second = await self.client.chat.completions.create(
                model=self.deployment,
                messages=history,
            )
            reply = second.choices[0].message.content or ""
            history.append({"role": "assistant", "content": reply})
            return reply, conv_id

        reply = first_message.content or ""
        history.append({"role": "assistant", "content": reply})
        return reply, conv_id

    async def _handle_tool_calls(self, tool_calls: list[Any]) -> list[dict[str, Any]]:
        tool_messages: list[dict[str, Any]] = []
        for tool_call in tool_calls:
            function_name = tool_call.function.name
            if function_name != "query_device_state":
                tool_messages.append(
                    {
                        "role": "tool",
                        "tool_call_id": tool_call.id,
                        "name": function_name,
                        "content": json.dumps({"error": "Unsupported tool"}),
                    }
                )
                continue
            try:
                arguments = json.loads(tool_call.function.arguments or "{}")
                device_id = arguments.get("deviceId")
                if not isinstance(device_id, str) or not device_id.strip():
                    raise ValueError("deviceId is required")
                state = await self.device_state_service.get_cached_device_state(device_id)
                content = json.dumps(state.model_dump())
            except Exception as exc:
                logger.warning("Tool query_device_state failed: %s", exc)
                content = json.dumps({"error": str(exc)})
            tool_messages.append(
                {
                    "role": "tool",
                    "tool_call_id": tool_call.id,
                    "name": "query_device_state",
                    "content": content,
                }
            )
        return tool_messages


@lru_cache(maxsize=1)
def get_openai_service() -> OpenAIChatService:
    return OpenAIChatService(device_state_service=get_device_state_service())
