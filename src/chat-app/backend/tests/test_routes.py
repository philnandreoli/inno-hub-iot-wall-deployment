from typing import Any

from fastapi.testclient import TestClient

from app.dependencies import get_publisher, get_status_reader, verify_token
from app.main import create_app


class FakePublisher:
    qos = 1

    def __init__(self) -> None:
        self.calls: list[dict[str, Any]] = []

    def publish_command(
        self,
        device_name: str,
        payload_data: dict[str, Any],
        message_expiry: int = 60,
    ) -> str:
        self.calls.append(
            {
                "device_name": device_name,
                "payload_data": payload_data,
                "message_expiry": message_expiry,
            }
        )
        return "corr-123"


class FakeStatusReader:
    def get_device_status(self, device_name: str) -> dict[str, Any]:
        if device_name == "missing-vm-k3s":
            raise LookupError("No status found")
        if device_name == "error-vm-k3s":
            raise RuntimeError("boom")

        return {
            "deviceName": device_name,
            "source": "fabric-eventhouse",
            "record": {"lamp": True},
        }

    def get_devices_by_hub(self) -> dict[str, Any]:
        return {
            "source": "fabric-eventhouse",
            "count": 1,
            "devicesByHub": [{"hub": "hub-1", "deviceName": "d1-vm-k3s"}],
        }

    def get_all_devices_status(self) -> dict[str, Any]:
        return {
            "source": "fabric-eventhouse",
            "count": 1,
            "devices": [{"deviceName": "d1-vm-k3s", "lamp": True}],
        }

    def get_device_telemetry(self, device_name: str, timespan: str = "7d") -> dict[str, Any]:
        if device_name == "error-vm-k3s":
            raise RuntimeError("boom")

        return {
            "deviceName": device_name,
            "timespan": timespan,
            "source": "fabric-eventhouse",
            "count": 1,
            "measurements": [
                {
                    "iotInstanceName": device_name,
                    "tag": "temperature",
                    "timestamp": "2026-04-19T14:59:11.6274447Z",
                    "value_long": 496,
                    "value_bool": None,
                }
            ],
        }


async def fake_verify_token() -> dict[str, str]:
    return {"sub": "test-user"}


def build_test_client() -> tuple[TestClient, FakePublisher]:
    app = create_app()
    publisher = FakePublisher()

    app.dependency_overrides[verify_token] = fake_verify_token
    app.dependency_overrides[get_publisher] = lambda: publisher
    app.dependency_overrides[get_status_reader] = lambda: FakeStatusReader()

    return TestClient(app), publisher


def test_lamp_on_publishes_expected_payload() -> None:
    client, publisher = build_test_client()

    response = client.post("/api/devices/device-1-vm-k3s/commands/lamp/on")

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "published"
    assert body["topic"] == "/iotoperations/device-1-vm-k3s/command"
    assert body["payload"] == {"lamp": True}
    assert body["qos"] == 1
    assert body["correlationData"] == "corr-123"
    assert publisher.calls[0]["message_expiry"] == 60


def test_invalid_device_name_returns_400() -> None:
    client, _ = build_test_client()

    response = client.post("/api/devices/invalid_name/commands/lamp/on")

    assert response.status_code == 400
    assert response.json()["detail"] == "Invalid device name"


def test_blink_pattern_out_of_range_returns_422() -> None:
    client, _ = build_test_client()

    response = client.post("/api/devices/device-1-vm-k3s/commands/blinkpattern/7")

    assert response.status_code == 422


def test_status_not_found_maps_to_404() -> None:
    client, _ = build_test_client()

    response = client.get("/api/devices/missing-vm-k3s/commands/status")

    assert response.status_code == 404


def test_status_runtime_error_maps_to_502() -> None:
    client, _ = build_test_client()

    response = client.get("/api/devices/error-vm-k3s/commands/status")

    assert response.status_code == 502
    assert response.json()["detail"] == "Failed to fetch device status"


def test_device_telemetry_default_timespan_is_7d() -> None:
    client, _ = build_test_client()

    response = client.get("/api/devices/device-1-vm-k3s/telemetry")

    assert response.status_code == 200
    body = response.json()
    assert body["deviceName"] == "device-1-vm-k3s"
    assert body["timespan"] == "7d"
    assert body["source"] == "fabric-eventhouse"
    assert body["measurements"][0]["tag"] == "temperature"
    assert set(body["measurements"][0].keys()) == {
        "iotInstanceName",
        "tag",
        "timestamp",
        "value_long",
        "value_bool",
    }
    assert "value" not in body["measurements"][0]
    assert "valueType" not in body["measurements"][0]


def test_device_telemetry_accepts_custom_timespan() -> None:
    client, _ = build_test_client()

    response = client.get("/api/devices/device-1-vm-k3s/telemetry?timespan=1h")

    assert response.status_code == 200
    body = response.json()
    assert body["timespan"] == "1h"


def test_device_telemetry_rejects_invalid_timespan() -> None:
    client, _ = build_test_client()

    response = client.get("/api/devices/device-1-vm-k3s/telemetry?timespan=bad")

    assert response.status_code == 400
    assert response.json()["detail"] == "Invalid timespan"
