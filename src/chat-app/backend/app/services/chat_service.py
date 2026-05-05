"""ChatService: natural language to IoT device commands via Azure OpenAI GPT function calling.

Session-scoped conversation history is held in-memory (not persisted).  Each
browser tab creates its own session ID so that concurrent users get independent
conversations.

Write tools (lamp / fan / blink) return a ``pending_action`` dict instead of
executing immediately.  The caller must confirm via ``confirm_action`` before
the MQTT command is published.  Read tools (status / telemetry) execute
immediately.
"""

import json
import logging
from typing import Any

from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from openai import AzureOpenAI

from app.config import Settings
from app.services.mqtt_publisher import MqttPublisher
from app.services.status_reader import EventhouseStatusReader

logger = logging.getLogger(__name__)

# Maximum messages retained per session (system + alternating user/assistant).
# Older messages beyond this limit are pruned (keeping the system prompt).
_MAX_HISTORY = 40

_SYSTEM_PROMPT = """You are an IoT operations assistant for an industrial hub that manages
Beckhoff PLCs and Leuze barcode readers connected via Azure IoT Operations.

You help operators control and monitor devices using natural language.

Available devices follow the naming convention: <location>-<identifier>-vm-k3s
(e.g. atl-azureiot-vm-k3s, dal-mtc2032-vm-k3s).

You have access to these tools:
- get_device_status: read the latest status of a device (executes immediately)
- get_device_telemetry: read historical telemetry for a device (executes immediately)
- set_lamp_state: turn the indicator lamp on or off (requires confirmation)
- set_fan_state: turn the cooling fan on or off (requires confirmation)
- set_blink_pattern: set the LED blink pattern 0-6 (requires confirmation)

For write commands (lamp, fan, blink), always describe what you are about to do
and wait for the user to confirm before the action is taken.

Keep responses concise and factual. If a device name is ambiguous, ask the
operator to clarify.
"""

_TOOLS: list[dict[str, Any]] = [
    {
        "type": "function",
        "function": {
            "name": "get_device_status",
            "description": (
                "Retrieve the latest status record for a device from Eventhouse. "
                "Returns lamp state, fan state, message counts, and connectivity info."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "device_name": {
                        "type": "string",
                        "description": "Device name (e.g. atl-azureiot-vm-k3s)",
                    },
                },
                "required": ["device_name"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_device_telemetry",
            "description": (
                "Retrieve recent telemetry measurements for a device from Eventhouse."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "device_name": {
                        "type": "string",
                        "description": "Device name (e.g. atl-azureiot-vm-k3s)",
                    },
                    "timespan": {
                        "type": "string",
                        "description": (
                            "KQL timespan for how far back to query, e.g. '1h', '6h', '1d', '7d'."
                        ),
                        "default": "1h",
                    },
                },
                "required": ["device_name"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "set_lamp_state",
            "description": "Turn the indicator lamp on or off on a device. Requires confirmation.",
            "parameters": {
                "type": "object",
                "properties": {
                    "device_name": {
                        "type": "string",
                        "description": "Device name (e.g. atl-azureiot-vm-k3s)",
                    },
                    "state": {
                        "type": "boolean",
                        "description": "True to turn the lamp on, False to turn it off.",
                    },
                },
                "required": ["device_name", "state"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "set_fan_state",
            "description": "Turn the cooling fan on or off on a device. Requires confirmation.",
            "parameters": {
                "type": "object",
                "properties": {
                    "device_name": {
                        "type": "string",
                        "description": "Device name (e.g. atl-azureiot-vm-k3s)",
                    },
                    "state": {
                        "type": "string",
                        "enum": ["on", "off"],
                        "description": "'on' to start the fan, 'off' to stop it.",
                    },
                },
                "required": ["device_name", "state"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "set_blink_pattern",
            "description": (
                "Set the LED blink pattern on a device (0 = off, 1-6 = patterns). "
                "Requires confirmation."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "device_name": {
                        "type": "string",
                        "description": "Device name (e.g. atl-azureiot-vm-k3s)",
                    },
                    "pattern_number": {
                        "type": "integer",
                        "minimum": 0,
                        "maximum": 6,
                        "description": "Blink pattern number (0-6).",
                    },
                },
                "required": ["device_name", "pattern_number"],
            },
        },
    },
]

# Tools that require human-in-the-loop confirmation before execution.
_WRITE_TOOLS = {"set_lamp_state", "set_fan_state", "set_blink_pattern"}


def _human_readable_action(func_name: str, args: dict[str, Any]) -> str:
    """Return a short human-readable description of a pending write action."""
    device = args.get("device_name", "unknown device")
    if func_name == "set_lamp_state":
        state = "ON" if args.get("state") else "OFF"
        return f"Turn lamp {state} on {device}"
    if func_name == "set_fan_state":
        state = str(args.get("state", "")).upper()
        return f"Turn fan {state} on {device}"
    if func_name == "set_blink_pattern":
        pattern = args.get("pattern_number", 0)
        return f"Set blink pattern {pattern} on {device}"
    return f"Execute {func_name} on {device}"


class ChatService:
    """Session-scoped natural-language chat service backed by Azure OpenAI."""

    def __init__(
        self,
        settings: Settings,
        publisher: MqttPublisher,
        status_reader: EventhouseStatusReader,
    ) -> None:
        if not settings.azure_openai_endpoint:
            raise RuntimeError(
                "Missing required environment variable: APP_AZURE_OPENAI_ENDPOINT"
            )

        token_provider = get_bearer_token_provider(
            DefaultAzureCredential(),
            "https://cognitiveservices.azure.com/.default",
        )
        self._client = AzureOpenAI(
            azure_endpoint=settings.azure_openai_endpoint,
            api_version=settings.azure_openai_api_version,
            azure_ad_token_provider=token_provider,
        )
        self._deployment = settings.azure_openai_deployment
        self._publisher = publisher
        self._status_reader = status_reader

        # session_id → list of OpenAI message dicts
        self._sessions: dict[str, list[dict[str, Any]]] = {}
        # session_id → pending write action waiting for confirmation
        self._pending: dict[str, dict[str, Any]] = {}

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def chat(self, session_id: str, user_message: str) -> dict[str, Any]:
        """Process a user message and return ``{message, pending_action}``.

        If the model wants to execute a write command, ``pending_action`` is
        populated and the command is NOT yet sent.  The caller must call
        ``confirm_action`` or ``cancel_action`` to resolve it.

        Read commands execute immediately and ``pending_action`` is ``None``.
        """
        history = self._get_or_create_session(session_id)
        history.append({"role": "user", "content": user_message})
        self._trim_history(history)

        response_message, pending_action = self._run_completion(session_id, history)
        return {"message": response_message, "pending_action": pending_action}

    def confirm_action(self, session_id: str) -> dict[str, Any]:
        """Execute the pending write action and return ``{message, pending_action}``."""
        pending = self._pending.pop(session_id, None)
        if pending is None:
            return {"message": "No pending action to confirm.", "pending_action": None}

        history = self._get_or_create_session(session_id)
        tool_call_id = pending["tool_call_id"]

        # Execute the actual device command
        try:
            result_content = self._execute_write_tool(
                pending["function_name"], pending["arguments"]
            )
        except Exception as exc:  # noqa: BLE001
            logger.exception(
                "Failed to execute confirmed action %s", pending["function_name"]
            )
            result_content = f"Error executing command: {exc}"

        # Append tool result so the model can summarise the outcome
        history.append({
            "role": "tool",
            "tool_call_id": tool_call_id,
            "content": result_content,
        })
        self._trim_history(history)

        response_message, pending_action = self._run_completion(session_id, history)
        return {"message": response_message, "pending_action": pending_action}

    def cancel_action(self, session_id: str) -> dict[str, Any]:
        """Cancel the pending write action and return ``{message, pending_action}``."""
        pending = self._pending.pop(session_id, None)
        if pending is None:
            return {"message": "No pending action to cancel.", "pending_action": None}

        history = self._get_or_create_session(session_id)
        history.append({
            "role": "tool",
            "tool_call_id": pending["tool_call_id"],
            "content": "Action was cancelled by the operator.",
        })
        self._trim_history(history)

        response_message, pending_action = self._run_completion(session_id, history)
        return {"message": response_message, "pending_action": pending_action}

    def clear_session(self, session_id: str) -> None:
        """Remove all conversation history and pending actions for a session."""
        self._sessions.pop(session_id, None)
        self._pending.pop(session_id, None)

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _get_or_create_session(self, session_id: str) -> list[dict[str, Any]]:
        if session_id not in self._sessions:
            self._sessions[session_id] = [
                {"role": "system", "content": _SYSTEM_PROMPT}
            ]
        return self._sessions[session_id]

    def _trim_history(self, history: list[dict[str, Any]]) -> None:
        """Keep the system prompt plus the most recent messages."""
        if len(history) > _MAX_HISTORY:
            # Always keep history[0] (system prompt)
            history[1:] = history[-((_MAX_HISTORY - 1)):]

    def _run_completion(
        self,
        session_id: str,
        history: list[dict[str, Any]],
    ) -> tuple[str, dict[str, Any] | None]:
        """Call the model; handle tool calls; return (message_text, pending_action)."""
        try:
            response = self._client.chat.completions.create(
                model=self._deployment,
                messages=history,
                tools=_TOOLS,
                tool_choice="auto",
            )
        except Exception as exc:  # noqa: BLE001
            logger.exception("Azure OpenAI request failed")
            return f"I'm unable to process your request right now: {exc}", None

        choice = response.choices[0]

        # No tool call — plain text response
        if choice.finish_reason != "tool_calls" or not choice.message.tool_calls:
            text = choice.message.content or ""
            history.append({"role": "assistant", "content": text})
            return text, None

        # Tool call requested
        tool_call = choice.message.tool_calls[0]
        func_name = tool_call.function.name
        try:
            args: dict[str, Any] = json.loads(tool_call.function.arguments)
        except json.JSONDecodeError:
            args = {}

        # Append assistant message with the tool call to history
        history.append(choice.message)

        if func_name in _WRITE_TOOLS:
            # Write tool — require human confirmation
            pending = {
                "tool_call_id": tool_call.id,
                "function_name": func_name,
                "arguments": args,
                "description": _human_readable_action(func_name, args),
            }
            self._pending[session_id] = pending

            confirmation_prompt = (
                f"I'm ready to: **{pending['description']}**. "
                "Please confirm to proceed, or cancel to abort."
            )
            return confirmation_prompt, {
                "function_name": func_name,
                "arguments": args,
                "description": pending["description"],
            }

        # Read tool — execute immediately
        try:
            result_content = self._execute_read_tool(func_name, args)
        except Exception as exc:  # noqa: BLE001
            logger.exception("Failed to execute read tool %s", func_name)
            result_content = f"Error: {exc}"

        history.append({
            "role": "tool",
            "tool_call_id": tool_call.id,
            "content": result_content,
        })
        self._trim_history(history)

        # Re-run completion so the model can interpret the tool result
        return self._run_completion(session_id, history)

    # ------------------------------------------------------------------
    # Tool executors
    # ------------------------------------------------------------------

    def _execute_read_tool(self, func_name: str, args: dict[str, Any]) -> str:
        device_name = args.get("device_name", "")

        if func_name == "get_device_status":
            try:
                result = self._status_reader.get_device_status(device_name=device_name)
                return json.dumps(result, default=str)
            except LookupError as exc:
                return f"Device '{device_name}' not found: {exc}"

        if func_name == "get_device_telemetry":
            timespan = args.get("timespan", "1h")
            try:
                result = self._status_reader.get_device_telemetry(
                    device_name=device_name,
                    timespan=timespan,
                )
                return json.dumps(result, default=str)
            except Exception as exc:  # noqa: BLE001
                return f"Telemetry query failed: {exc}"

        return f"Unknown read tool: {func_name}"

    def _execute_write_tool(self, func_name: str, args: dict[str, Any]) -> str:
        device_name = args.get("device_name", "")

        if func_name == "set_lamp_state":
            state: bool = bool(args.get("state", False))
            payload = {"lamp": state}
            expiry = 60 if state else 5
            correlation_id = self._publisher.publish_command(
                device_name=device_name,
                payload_data=payload,
                message_expiry=expiry,
            )
            return json.dumps({
                "status": "published",
                "correlationId": correlation_id,
                "payload": payload,
            })

        if func_name == "set_fan_state":
            state_str: str = str(args.get("state", "off")).lower()
            fan_value = 32000 if state_str == "on" else 0
            payload = {"fan": fan_value}
            expiry = 60 if state_str == "on" else 5
            correlation_id = self._publisher.publish_command(
                device_name=device_name,
                payload_data=payload,
                message_expiry=expiry,
            )
            return json.dumps({
                "status": "published",
                "correlationId": correlation_id,
                "payload": payload,
            })

        if func_name == "set_blink_pattern":
            pattern = int(args.get("pattern_number", 0))
            payload = {"blinkPattern": pattern}
            correlation_id = self._publisher.publish_command(
                device_name=device_name,
                payload_data=payload,
                message_expiry=5,
            )
            return json.dumps({
                "status": "published",
                "correlationId": correlation_id,
                "payload": payload,
            })

        return f"Unknown write tool: {func_name}"
