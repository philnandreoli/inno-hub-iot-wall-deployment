"""Response model contract tests.

These tests verify that every endpoint returns a response that conforms
to its declared Pydantic ``response_model``.  Specifically:

- Required fields are present in the JSON body.
- Field names are stable camelCase (no snake_case leakage, no fallback
  chains needed on the frontend).
- Numeric/boolean types are preserved (e.g. ``messagesLast24h`` is an int).
- The OpenAPI schema includes each endpoint's ``response_model``.
"""

from __future__ import annotations

import os
from typing import Any
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient

from app.dependencies import (
    get_arc_status_reader,
    get_publisher,
    get_status_reader,
    verify_token,
)
from app.main import create_app
from app.models.responses import (
    AllDevicesStatusResponse,
    ArcResource,
    ArcStatusResponse,
    CommandResponse,
    DevicesByHubResponse,
    DeviceStatusResponse,
    DeviceTelemetryResponse,
    HealthResponse,
    TelemetryMeasurement,
)


# ---------------------------------------------------------------------------
# Fakes (identical contract to test_routes.py / test_arc_status.py)
# ---------------------------------------------------------------------------

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
        self.calls.append({"device_name": device_name, "payload_data": payload_data})
        return "corr-abc"


class FakeStatusReader:
    def get_device_status(self, device_name: str) -> dict[str, Any]:
        return {
            "deviceName": device_name,
            "source": "fabric-eventhouse",
            "record": {"lamp": True, "messagesLast24h": 42},
        }

    def get_devices_by_hub(self) -> dict[str, Any]:
        return {
            "source": "fabric-eventhouse",
            "count": 2,
            "devicesByHub": [
                {"hub": "ATL", "deviceName": "atl-azureiot-vm-k3s"},
                {"hub": "DAL", "deviceName": "dal-azureiot-vm-k3s"},
            ],
        }

    def get_all_devices_status(self) -> dict[str, Any]:
        return {
            "source": "fabric-eventhouse",
            "count": 1,
            "devices": [{"deviceName": "atl-azureiot-vm-k3s", "lamp": True, "messagesLast24h": 10}],
        }

    def get_device_telemetry(
        self,
        device_name: str,
        timespan: str | None = "7d",
        start_date: Any = None,
        end_date: Any = None,
    ) -> dict[str, Any]:
        return {
            "deviceName": device_name,
            "timespan": timespan,
            "startDate": start_date,
            "endDate": end_date,
            "source": "fabric-eventhouse",
            "count": 1,
            "measurements": [
                {
                    "iotInstanceName": device_name,
                    "tag": "temperature",
                    "timestamp": "2026-04-19T14:59:11.6274447Z",
                    "value_long": 250,
                    "value_bool": None,
                }
            ],
        }


class FakeArcStatusReader:
    def get_arc_status(self, device_name: str, hub: str, country: str) -> dict[str, Any]:
        rg = f"EXP-MFG-AIO-{hub.upper()}-{country.upper()}-RG"
        return {
            "deviceName": device_name,
            "resourceGroup": rg,
            "host": {
                "resourceName": "azureiot",
                "resourceType": "Microsoft.HybridCompute/machines",
                "status": "Connected",
            },
            "vm": {
                "resourceName": "azureiot-vm",
                "resourceType": "Microsoft.HybridCompute/machines",
                "status": "Connected",
            },
            "k8sCluster": {
                "resourceName": device_name,
                "resourceType": "Microsoft.Kubernetes/connectedClusters",
                "status": "Connected",
            },
        }


async def fake_verify_token() -> dict[str, str]:
    return {"sub": "test-user"}


def build_client() -> tuple[TestClient, FakePublisher]:
    app = create_app()
    publisher = FakePublisher()
    app.dependency_overrides[verify_token] = fake_verify_token
    app.dependency_overrides[get_publisher] = lambda: publisher
    app.dependency_overrides[get_status_reader] = lambda: FakeStatusReader()
    app.dependency_overrides[get_arc_status_reader] = lambda: FakeArcStatusReader()
    return TestClient(app), publisher


# ---------------------------------------------------------------------------
# Model unit tests (no HTTP, just Pydantic)
# ---------------------------------------------------------------------------

def test_health_response_model() -> None:
    model = HealthResponse(status="ok")
    assert model.status == "ok"


def test_command_response_model() -> None:
    model = CommandResponse(
        status="published",
        topic="/iotoperations/dev-vm-k3s/command",
        payload={"lamp": True},
        qos=1,
        correlationData="corr-001",
    )
    assert model.status == "published"
    assert model.correlationData == "corr-001"
    assert model.payload == {"lamp": True}


def test_telemetry_measurement_model_allows_null_fields() -> None:
    m = TelemetryMeasurement(
        iotInstanceName=None,
        tag="temperature",
        timestamp="2026-01-01T00:00:00Z",
        value_long=100.0,
        value_bool=None,
    )
    assert m.tag == "temperature"
    assert m.iotInstanceName is None
    assert m.value_bool is None


def test_arc_resource_model() -> None:
    r = ArcResource(
        resourceName="azureiot",
        resourceType="Microsoft.HybridCompute/machines",
        status="Connected",
    )
    assert r.resourceType == "Microsoft.HybridCompute/machines"


def test_arc_status_response_model_nesting() -> None:
    model = ArcStatusResponse(
        deviceName="atl-azureiot-vm-k3s",
        resourceGroup="EXP-MFG-AIO-ATL-US-RG",
        host=ArcResource(
            resourceName="azureiot",
            resourceType="Microsoft.HybridCompute/machines",
            status="Connected",
        ),
        vm=ArcResource(
            resourceName="azureiot-vm",
            resourceType="Microsoft.HybridCompute/machines",
            status="Connected",
        ),
        k8sCluster=ArcResource(
            resourceName="atl-azureiot-vm-k3s",
            resourceType="Microsoft.Kubernetes/connectedClusters",
            status="Connected",
        ),
    )
    assert model.host.resourceName == "azureiot"
    assert model.k8sCluster.resourceType == "Microsoft.Kubernetes/connectedClusters"


# ---------------------------------------------------------------------------
# Endpoint shape contract tests
# ---------------------------------------------------------------------------

def test_health_endpoint_response_shape() -> None:
    client, _ = build_client()
    res = client.get("/health")
    assert res.status_code == 200
    body = res.json()
    # Validate via model — raises ValidationError if shape is wrong
    HealthResponse(**body)
    assert body["status"] == "ok"


def test_device_status_response_shape() -> None:
    client, _ = build_client()
    res = client.get("/api/devices/atl-azureiot-vm-k3s/commands/status")
    assert res.status_code == 200
    body = res.json()
    DeviceStatusResponse(**body)
    assert body["deviceName"] == "atl-azureiot-vm-k3s"
    assert body["source"] == "fabric-eventhouse"
    assert isinstance(body["record"], dict)


def test_all_devices_status_response_shape() -> None:
    client, _ = build_client()
    res = client.get("/api/devices/commands/status")
    assert res.status_code == 200
    body = res.json()
    AllDevicesStatusResponse(**body)
    assert body["source"] == "fabric-eventhouse"
    assert isinstance(body["count"], int)
    assert isinstance(body["devices"], list)


def test_devices_by_hub_response_shape() -> None:
    client, _ = build_client()
    res = client.get("/api/devices/by-hub")
    assert res.status_code == 200
    body = res.json()
    DevicesByHubResponse(**body)
    assert body["source"] == "fabric-eventhouse"
    assert isinstance(body["count"], int)
    assert isinstance(body["devicesByHub"], list)
    # Hub entries must be dicts with at least a "hub" key
    for entry in body["devicesByHub"]:
        assert "hub" in entry


def test_telemetry_response_shape() -> None:
    client, _ = build_client()
    res = client.get("/api/devices/atl-azureiot-vm-k3s/telemetry")
    assert res.status_code == 200
    body = res.json()
    DeviceTelemetryResponse(**body)
    assert body["deviceName"] == "atl-azureiot-vm-k3s"
    assert body["source"] == "fabric-eventhouse"
    assert isinstance(body["count"], int)
    assert isinstance(body["measurements"], list)


def test_telemetry_measurement_fields_are_stable() -> None:
    """Measurement rows must use exactly the documented field names."""
    client, _ = build_client()
    res = client.get("/api/devices/atl-azureiot-vm-k3s/telemetry")
    assert res.status_code == 200
    body = res.json()
    assert len(body["measurements"]) > 0
    m = body["measurements"][0]
    # All five fields must be present (may be null, but must exist)
    for field in ("iotInstanceName", "tag", "timestamp", "value_long", "value_bool"):
        assert field in m, f"Expected field '{field}' in measurement row"
    # No legacy snake_case leakage from the raw Kusto row
    assert "iot_instance_name" not in m


def test_arc_status_response_shape() -> None:
    client, _ = build_client()
    res = client.get("/api/devices/atl-azureiot-vm-k3s/arc-status")
    assert res.status_code == 200
    body = res.json()
    ArcStatusResponse(**body)
    assert body["deviceName"] == "atl-azureiot-vm-k3s"
    assert body["resourceGroup"] == "EXP-MFG-AIO-ATL-US-RG"
    for resource_key in ("host", "vm", "k8sCluster"):
        assert resource_key in body
        for field in ("resourceName", "resourceType", "status"):
            assert field in body[resource_key]


@pytest.mark.parametrize(
    "url,payload_key,payload_value",
    [
        ("/api/devices/atl-azureiot-vm-k3s/commands/lamp/on", "lamp", True),
        ("/api/devices/atl-azureiot-vm-k3s/commands/lamp/off", "lamp", False),
        ("/api/devices/atl-azureiot-vm-k3s/commands/fan/on", "fan", 32000),
        ("/api/devices/atl-azureiot-vm-k3s/commands/fan/off", "fan", 0),
    ],
)
def test_command_response_shape(url: str, payload_key: str, payload_value: Any) -> None:
    client, _ = build_client()
    res = client.post(url)
    assert res.status_code == 200
    body = res.json()
    CommandResponse(**body)
    assert body["status"] == "published"
    assert "topic" in body
    assert "qos" in body
    assert "correlationData" in body
    assert body["payload"][payload_key] == payload_value


def test_blink_pattern_command_response_shape() -> None:
    client, _ = build_client()
    res = client.post("/api/devices/atl-azureiot-vm-k3s/commands/blinkpattern/3")
    assert res.status_code == 200
    body = res.json()
    CommandResponse(**body)
    assert body["payload"] == {"blinkPattern": 3}


# ---------------------------------------------------------------------------
# OpenAPI schema tests — response_model appears in the schema
# ---------------------------------------------------------------------------

def test_openapi_schema_includes_health_response_model() -> None:
    with patch.dict(os.environ, {"ENABLE_DOCS": "true"}, clear=False):
        app = create_app()
        client = TestClient(app)
        schema = client.get("/openapi.json").json()
    health_schema = schema["paths"]["/health"]["get"]["responses"]["200"]
    assert "content" in health_schema
    ref = health_schema["content"]["application/json"]["schema"]
    # Either a direct $ref or allOf wrapper — either way must reference HealthResponse
    schema_str = str(ref)
    assert "HealthResponse" in schema_str


def test_openapi_schema_includes_device_status_response_model() -> None:
    with patch.dict(os.environ, {"ENABLE_DOCS": "true"}, clear=False):
        app = create_app()
        client = TestClient(app)
        schema = client.get("/openapi.json").json()
    path_schema = schema["paths"]["/api/devices/{device_name}/commands/status"]["get"]
    resp_200 = path_schema["responses"]["200"]
    schema_str = str(resp_200)
    assert "DeviceStatusResponse" in schema_str


def test_openapi_schema_includes_command_response_model() -> None:
    with patch.dict(os.environ, {"ENABLE_DOCS": "true"}, clear=False):
        app = create_app()
        client = TestClient(app)
        schema = client.get("/openapi.json").json()
    path_schema = schema["paths"]["/api/devices/{device_name}/commands/lamp/on"]["post"]
    resp_200 = path_schema["responses"]["200"]
    schema_str = str(resp_200)
    assert "CommandResponse" in schema_str


def test_openapi_schema_includes_telemetry_response_model() -> None:
    with patch.dict(os.environ, {"ENABLE_DOCS": "true"}, clear=False):
        app = create_app()
        client = TestClient(app)
        schema = client.get("/openapi.json").json()
    path_schema = schema["paths"]["/api/devices/{device_name}/telemetry"]["get"]
    resp_200 = path_schema["responses"]["200"]
    schema_str = str(resp_200)
    assert "DeviceTelemetryResponse" in schema_str


def test_openapi_schema_includes_arc_status_response_model() -> None:
    with patch.dict(os.environ, {"ENABLE_DOCS": "true"}, clear=False):
        app = create_app()
        client = TestClient(app)
        schema = client.get("/openapi.json").json()
    path_schema = schema["paths"]["/api/devices/{device_name}/arc-status"]["get"]
    resp_200 = path_schema["responses"]["200"]
    schema_str = str(resp_200)
    assert "ArcStatusResponse" in schema_str
