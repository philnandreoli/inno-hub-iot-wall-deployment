from typing import Any

from fastapi.testclient import TestClient

from app.dependencies import get_azure_vm_status_reader, get_publisher, get_status_reader, verify_token
from app.main import create_app
from app.services.azure_vm_status import AzureVmStatusReader
from app.services.status_reader import EventhouseStatusReader


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

        record: dict[str, Any] = {"lamp": True}
        if device_name == "device-with-vm-k3s":
            record["vmName"] = "my-azure-vm"

        return {
            "deviceName": device_name,
            "source": "fabric-eventhouse",
            "record": record,
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

    def get_device_telemetry(
        self,
        device_name: str,
        timespan: str | None = "7d",
        start_date: Any = None,
        end_date: Any = None,
    ) -> dict[str, Any]:
        if device_name == "error-vm-k3s":
            raise RuntimeError("boom")

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
                    "value_long": 496,
                    "value_bool": None,
                }
            ],
        }


class FakeAzureVmStatusReader:
    """Fake AzureVmStatusReader that returns a fixed running status when an identifier is present."""

    def get_vm_status(self, device_name: str, record: dict[str, Any]) -> dict[str, Any]:
        vm_identifier = AzureVmStatusReader.extract_vm_identifier(record)
        if not vm_identifier:
            return {
                "deviceName": device_name,
                "azureStatus": "Not Implemented",
                "identifier": None,
            }
        return {
            "deviceName": device_name,
            "azureStatus": "VM running",
            "identifier": vm_identifier,
        }


async def fake_verify_token() -> dict[str, str]:
    return {"sub": "test-user"}


def build_test_client() -> tuple[TestClient, FakePublisher]:
    app = create_app()
    publisher = FakePublisher()

    app.dependency_overrides[verify_token] = fake_verify_token
    app.dependency_overrides[get_publisher] = lambda: publisher
    app.dependency_overrides[get_status_reader] = lambda: FakeStatusReader()
    app.dependency_overrides[get_azure_vm_status_reader] = lambda: FakeAzureVmStatusReader()

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


def test_device_telemetry_accepts_date_range() -> None:
    client, _ = build_test_client()

    response = client.get(
        "/api/devices/device-1-vm-k3s/telemetry?"
        "startDate=2026-04-24T00:00:00Z&endDate=2026-04-25T00:00:00Z"
    )

    assert response.status_code == 200
    body = response.json()
    assert body["startDate"] == "2026-04-24T00:00:00Z"
    assert body["endDate"] == "2026-04-25T00:00:00Z"


def test_device_telemetry_rejects_partial_date_range() -> None:
    client, _ = build_test_client()

    response = client.get("/api/devices/device-1-vm-k3s/telemetry?startDate=2026-04-24T00:00:00Z")

    assert response.status_code == 400
    assert response.json()["detail"] == "Both startDate and endDate are required when filtering by date range"


def test_device_telemetry_rejects_invalid_date_order() -> None:
    client, _ = build_test_client()

    response = client.get(
        "/api/devices/device-1-vm-k3s/telemetry?"
        "startDate=2026-04-25T00:00:00Z&endDate=2026-04-24T00:00:00Z"
    )

    assert response.status_code == 400
    assert response.json()["detail"] == "startDate must be before endDate"


def test_device_telemetry_rejects_invalid_timespan() -> None:
    client, _ = build_test_client()

    response = client.get("/api/devices/device-1-vm-k3s/telemetry?timespan=bad")

    assert response.status_code == 400
    assert response.json()["detail"] == "Invalid timespan"


def test_status_row_normalization_maps_required_lueze_fields() -> None:
    reader = EventhouseStatusReader.__new__(EventhouseStatusReader)
    row = {
        "messages_last_24h": "8594",
        "luezeMessagesLast24h": 1322,
        "luezelastReadBarcode": "Leuze Barcodereader",
        "lueze_barcode_ingestion_time": "2026-04-21 20:31:21.9388722",
    }

    normalized = reader._normalize_status_row(row)

    assert normalized["messagesLast24h"] == 8594
    assert normalized["luezeMessagesLast24h"] == 1322
    assert normalized["luezeLastReadBarcode"] == "Leuze Barcodereader"
    assert normalized["luezelastReadBarcode"] == "Leuze Barcodereader"
    assert normalized["luezeBarcodeIngestionTime"] == "2026-04-21 20:31:21.9388722"


def test_status_row_normalization_defaults_missing_required_fields() -> None:
    reader = EventhouseStatusReader.__new__(EventhouseStatusReader)

    normalized = reader._normalize_status_row({"deviceName": "d1-vm-k3s"})

    assert normalized["messagesLast24h"] == 0
    assert normalized["luezeMessagesLast24h"] == 0
    assert normalized["luezeLastReadBarcode"] is None
    assert normalized["luezeBarcodeIngestionTime"] is None


# ── Azure VM Status ──────────────────────────────────────────────────────────

def test_azure_status_returns_not_implemented_when_no_identifier() -> None:
    client, _ = build_test_client()

    # device-1-vm-k3s has no vmName/hostName/instanceName in FakeStatusReader
    response = client.get("/api/devices/device-1-vm-k3s/azure-status")

    assert response.status_code == 200
    body = response.json()
    assert body["azureStatus"] == "Not Implemented"
    assert body["identifier"] is None
    assert body["deviceName"] == "device-1-vm-k3s"


def test_azure_status_returns_running_when_identifier_present() -> None:
    client, _ = build_test_client()

    # device-with-vm-k3s has vmName="my-azure-vm" in FakeStatusReader
    response = client.get("/api/devices/device-with-vm-k3s/azure-status")

    assert response.status_code == 200
    body = response.json()
    assert body["azureStatus"] == "VM running"
    assert body["identifier"] == "my-azure-vm"
    assert body["deviceName"] == "device-with-vm-k3s"


def test_azure_status_returns_not_implemented_when_device_missing() -> None:
    client, _ = build_test_client()

    # missing-vm-k3s raises LookupError in FakeStatusReader
    response = client.get("/api/devices/missing-vm-k3s/azure-status")

    assert response.status_code == 200
    body = response.json()
    assert body["azureStatus"] == "Not Implemented"
    assert body["identifier"] is None


def test_azure_status_rejects_invalid_device_name() -> None:
    client, _ = build_test_client()

    response = client.get("/api/devices/invalid_name/azure-status")

    assert response.status_code == 400


def test_azure_vm_status_extract_identifier_vmname() -> None:
    record = {"vmName": "my-vm", "lamp": True}
    assert AzureVmStatusReader.extract_vm_identifier(record) == "my-vm"


def test_azure_vm_status_extract_identifier_hostname() -> None:
    record = {"hostName": "my-host"}
    assert AzureVmStatusReader.extract_vm_identifier(record) == "my-host"


def test_azure_vm_status_extract_identifier_instancename() -> None:
    record = {"instanceName": "my-instance"}
    assert AzureVmStatusReader.extract_vm_identifier(record) == "my-instance"


def test_azure_vm_status_extract_identifier_returns_none_when_absent() -> None:
    record = {"lamp": True, "messagesLast24h": 10}
    assert AzureVmStatusReader.extract_vm_identifier(record) is None


def test_azure_vm_status_not_implemented_when_unconfigured() -> None:
    from app.config import Settings

    settings = Settings(
        azure_tenant_id="t",
        azure_client_id="c",
        azure_eventgrid_mqtt_host="",
        azure_eventgrid_mqtt_port=8883,
        azure_eventgrid_mqtt_client_id="",
        mqtt_qos=1,
        mqtt_response_topic="",
        fabric_eventhouse_query_uri="",
        fabric_eventhouse_database="",
        fabric_eventhouse_query_retries=1,
        applicationinsights_connection_string="",
        enable_docs=False,
        azure_subscription_id="",
        azure_resource_group="",
    )

    reader = AzureVmStatusReader(settings)
    result = reader.get_vm_status("my-device", {"vmName": "some-vm"})

    assert result["azureStatus"] == "Not Implemented"
    assert result["identifier"] == "some-vm"
