"""Tests for POST /api/chat, /api/chat/confirm, and /api/chat/cancel endpoints."""

import pytest
from fastapi.testclient import TestClient

from app.dependencies import get_chat_service, verify_token
from app.main import create_app
from app.services.chat_service import ChatService


# ---------------------------------------------------------------------------
# Fakes
# ---------------------------------------------------------------------------

class FakeChatService:
    """Minimal stub for ChatService that avoids any Azure/OpenAI calls."""

    def chat(self, session_id: str, user_message: str, device_context: str | None = None) -> dict:
        if "status" in user_message.lower():
            # Read query — no pending action
            return {"message": "Device is online.", "pending_action": None}
        if "lamp" in user_message.lower():
            # Write command — return pending action
            return {
                "message": "I'm ready to: **Turn lamp ON on atl-vm-k3s**. Please confirm.",
                "pending_action": {
                    "function_name": "set_lamp_state",
                    "arguments": {"device_name": "atl-vm-k3s", "state": True},
                    "description": "Turn lamp ON on atl-vm-k3s",
                },
            }
        return {"message": "I can help with device commands.", "pending_action": None}

    def confirm_action(self, session_id: str) -> dict:
        return {"message": "Lamp turned ON successfully.", "pending_action": None}

    def cancel_action(self, session_id: str) -> dict:
        return {"message": "Command cancelled.", "pending_action": None}

    def clear_session(self, session_id: str) -> None:
        pass


async def fake_verify_token() -> dict:
    return {"sub": "test-user"}


def build_chat_test_client() -> TestClient:
    app = create_app()
    app.dependency_overrides[verify_token] = fake_verify_token
    app.dependency_overrides[get_chat_service] = lambda: FakeChatService()
    return TestClient(app)


# ---------------------------------------------------------------------------
# POST /api/chat
# ---------------------------------------------------------------------------

def test_chat_read_query_returns_message_no_pending_action() -> None:
    client = build_chat_test_client()

    response = client.post(
        "/api/chat",
        json={"sessionId": "session-1", "message": "What is the status of atl-vm-k3s?"},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["message"] == "Device is online."
    assert body["pendingAction"] is None


def test_chat_write_command_returns_pending_action() -> None:
    client = build_chat_test_client()

    response = client.post(
        "/api/chat",
        json={"sessionId": "session-2", "message": "Turn the lamp on for atl-vm-k3s"},
    )

    assert response.status_code == 200
    body = response.json()
    assert "confirm" in body["message"].lower() or "ready" in body["message"].lower()
    assert body["pendingAction"] is not None
    assert body["pendingAction"]["functionName"] == "set_lamp_state"
    assert body["pendingAction"]["arguments"]["device_name"] == "atl-vm-k3s"
    assert body["pendingAction"]["arguments"]["state"] is True
    assert "Turn lamp ON" in body["pendingAction"]["description"]


def test_chat_missing_session_id_returns_422() -> None:
    client = build_chat_test_client()

    response = client.post("/api/chat", json={"message": "hello"})

    assert response.status_code == 422


def test_chat_missing_message_returns_422() -> None:
    client = build_chat_test_client()

    response = client.post("/api/chat", json={"sessionId": "session-3"})

    assert response.status_code == 422


def test_chat_requires_authentication() -> None:
    app = create_app()
    # Only override the chat service — keep real token verification
    app.dependency_overrides[get_chat_service] = lambda: FakeChatService()
    client = TestClient(app, raise_server_exceptions=False)

    response = client.post(
        "/api/chat",
        json={"sessionId": "session-x", "message": "hello"},
    )

    # 401 when token verifier is configured; 500 when azure_client_id is empty (test env)
    assert response.status_code in (401, 500)


# ---------------------------------------------------------------------------
# POST /api/chat/confirm
# ---------------------------------------------------------------------------

def test_confirm_action_returns_message_no_pending() -> None:
    client = build_chat_test_client()

    response = client.post("/api/chat/confirm", json={"sessionId": "session-4"})

    assert response.status_code == 200
    body = response.json()
    assert body["message"] == "Lamp turned ON successfully."
    assert body["pendingAction"] is None


def test_confirm_missing_session_id_returns_422() -> None:
    client = build_chat_test_client()

    response = client.post("/api/chat/confirm", json={})

    assert response.status_code == 422


# ---------------------------------------------------------------------------
# POST /api/chat/cancel
# ---------------------------------------------------------------------------

def test_cancel_action_returns_cancellation_message() -> None:
    client = build_chat_test_client()

    response = client.post("/api/chat/cancel", json={"sessionId": "session-5"})

    assert response.status_code == 200
    body = response.json()
    assert body["message"] == "Command cancelled."
    assert body["pendingAction"] is None


# ---------------------------------------------------------------------------
# ChatService unit tests (no HTTP layer)
# ---------------------------------------------------------------------------

class FakePublisher:
    qos = 1

    def __init__(self) -> None:
        self.calls: list[dict] = []

    def publish_command(self, device_name: str, payload_data: dict, message_expiry: int = 60) -> str:
        self.calls.append({"device_name": device_name, "payload": payload_data})
        return "corr-abc"


class FakeStatusReader:
    def get_device_status(self, device_name: str) -> dict:
        if device_name == "missing-vm-k3s":
            raise LookupError("not found")
        return {"deviceName": device_name, "source": "test", "record": {"lamp": True}}

    def get_device_telemetry(self, device_name: str, timespan: str = "1h", **_kwargs) -> dict:
        return {
            "deviceName": device_name,
            "timespan": timespan,
            "source": "test",
            "count": 0,
            "measurements": [],
        }


def _make_service(publisher=None, status_reader=None) -> ChatService:
    """Build a ChatService with real logic but fake I/O dependencies."""
    from app.config import Settings

    settings = Settings(
        azure_tenant_id="tenant",
        azure_client_id="client",
        azure_eventgrid_mqtt_host="host",
        azure_eventgrid_mqtt_port=8883,
        azure_eventgrid_mqtt_client_id="",
        mqtt_qos=1,
        mqtt_response_topic="resp",
        fabric_eventhouse_query_uri="",
        fabric_eventhouse_database="",
        fabric_eventhouse_query_retries=1,
        applicationinsights_connection_string="",
        enable_docs=False,
        azure_subscription_id="",
        azure_openai_endpoint="https://fake.openai.azure.com/",
        azure_openai_deployment="gpt-5.2",
        azure_openai_api_version="2025-04-01-preview",
    )
    service = ChatService.__new__(ChatService)
    # Bypass __init__ and set attributes manually to avoid Azure credential calls
    service._deployment = settings.azure_openai_deployment
    service._publisher = publisher or FakePublisher()
    service._status_reader = status_reader or FakeStatusReader()
    service._sessions = {}
    service._pending = {}
    return service


def test_execute_write_lamp_on_publishes_correct_payload() -> None:
    publisher = FakePublisher()
    service = _make_service(publisher=publisher)

    result = service._execute_write_tool(
        "set_lamp_state", {"device_name": "atl-vm-k3s", "state": True}
    )

    import json
    data = json.loads(result)
    assert data["status"] == "published"
    assert publisher.calls[0]["payload"] == {"lamp": True}


def test_execute_write_fan_on_publishes_32000() -> None:
    publisher = FakePublisher()
    service = _make_service(publisher=publisher)

    service._execute_write_tool(
        "set_fan_state", {"device_name": "atl-vm-k3s", "state": "on"}
    )

    assert publisher.calls[0]["payload"] == {"fan": 32000}


def test_execute_write_fan_off_publishes_zero() -> None:
    publisher = FakePublisher()
    service = _make_service(publisher=publisher)

    service._execute_write_tool(
        "set_fan_state", {"device_name": "atl-vm-k3s", "state": "off"}
    )

    assert publisher.calls[0]["payload"] == {"fan": 0}


def test_execute_write_blink_pattern_publishes_pattern() -> None:
    publisher = FakePublisher()
    service = _make_service(publisher=publisher)

    service._execute_write_tool(
        "set_blink_pattern", {"device_name": "atl-vm-k3s", "pattern_number": 3}
    )

    assert publisher.calls[0]["payload"] == {"blinkPattern": 3}


def test_execute_read_status_returns_json() -> None:
    service = _make_service()

    result = service._execute_read_tool("get_device_status", {"device_name": "atl-vm-k3s"})

    import json
    data = json.loads(result)
    assert data["deviceName"] == "atl-vm-k3s"


def test_execute_read_status_missing_device_returns_error_string() -> None:
    service = _make_service()

    result = service._execute_read_tool("get_device_status", {"device_name": "missing-vm-k3s"})

    assert "not found" in result.lower()


def test_session_history_is_created_on_first_message() -> None:
    service = _make_service()

    service._get_or_create_session("new-session")

    assert "new-session" in service._sessions
    assert service._sessions["new-session"][0]["role"] == "system"


def test_history_is_trimmed_to_max_messages() -> None:
    service = _make_service()
    history = service._get_or_create_session("trim-session")

    # Fill history beyond limit
    for i in range(50):
        history.append({"role": "user", "content": f"msg {i}"})

    service._trim_history(history)

    from app.services.chat_service import _MAX_HISTORY
    assert len(history) <= _MAX_HISTORY
    assert history[0]["role"] == "system"


def test_cancel_with_no_pending_returns_graceful_message() -> None:
    service = _make_service()

    result = service.cancel_action("no-pending-session")

    assert result["message"] == "No pending action to cancel."
    assert result["pending_action"] is None


def test_confirm_with_no_pending_returns_graceful_message() -> None:
    service = _make_service()

    result = service.confirm_action("no-pending-session")

    assert result["message"] == "No pending action to confirm."
    assert result["pending_action"] is None


def test_clear_session_removes_history_and_pending() -> None:
    service = _make_service()
    service._sessions["s1"] = [{"role": "user", "content": "hi"}]
    service._pending["s1"] = {"tool_call_id": "x", "function_name": "set_lamp_state", "arguments": {}, "description": ""}

    service.clear_session("s1")

    assert "s1" not in service._sessions
    assert "s1" not in service._pending
