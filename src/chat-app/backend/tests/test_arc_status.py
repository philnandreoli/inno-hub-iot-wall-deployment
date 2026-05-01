import pytest
from typing import Any

from fastapi.testclient import TestClient

from app.dependencies import get_arc_status_reader, get_status_reader, verify_token
from app.main import create_app
from app.services.arc_status_reader import ArcStatusReader


# ---------------------------------------------------------------------------
# Fake dependencies
# ---------------------------------------------------------------------------

class FakeStatusReaderForArc:
    def get_device_status(self, device_name: str) -> dict[str, Any]:
        if device_name == "missing-vm-k3s":
            raise LookupError("No status found for device 'missing-vm-k3s'")
        if device_name == "kusto-error-vm-k3s":
            raise RuntimeError("Kusto boom")
        if device_name == "no-country-vm-k3s":
            return {
                "deviceName": device_name,
                "source": "fabric-eventhouse",
                "record": {"hub": "ATL"},
            }
        return {
            "deviceName": device_name,
            "source": "fabric-eventhouse",
            "record": {"hub": "ATL", "country": "US", "lamp": True},
        }


class FakeArcStatusReader:
    def get_arc_status(self, device_name: str, hub: str, country: str) -> dict[str, Any]:
        if "arc-notfound" in device_name:
            raise LookupError(f"ConnectedCluster '{device_name}' not found")
        if "arc-error" in device_name:
            raise RuntimeError("ARM failure")
        return {
            "deviceName": device_name,
            "resourceGroup": f"EXP-MFG-AIO-{hub.upper()}-{country.upper()}-RG",
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


def build_arc_test_client() -> TestClient:
    app = create_app()
    app.dependency_overrides[verify_token] = fake_verify_token
    app.dependency_overrides[get_status_reader] = lambda: FakeStatusReaderForArc()
    app.dependency_overrides[get_arc_status_reader] = lambda: FakeArcStatusReader()
    return TestClient(app)


# ---------------------------------------------------------------------------
# Unit tests: ArcStatusReader.derive_resource_names
# ---------------------------------------------------------------------------

@pytest.mark.parametrize(
    "cluster_name,expected_k8s,expected_vm,expected_host",
    [
        ("atl-azureiot-vm-k3s", "atl-azureiot-vm-k3s", "azureiot-vm", "azureiot"),
        ("nyc-mydevice-vm-k3s", "nyc-mydevice-vm-k3s", "mydevice-vm", "mydevice"),
        ("lon-factory01-vm-k3s", "lon-factory01-vm-k3s", "factory01-vm", "factory01"),
    ],
)
def test_derive_resource_names(
    cluster_name: str,
    expected_k8s: str,
    expected_vm: str,
    expected_host: str,
) -> None:
    k8s, vm, host = ArcStatusReader.derive_resource_names(cluster_name)
    assert k8s == expected_k8s
    assert vm == expected_vm
    assert host == expected_host


def test_derive_resource_names_raises_on_missing_dash() -> None:
    with pytest.raises(ValueError, match="no '-' separator"):
        ArcStatusReader.derive_resource_names("nodashname")


# ---------------------------------------------------------------------------
# Unit tests: ArcStatusReader.build_resource_group
# ---------------------------------------------------------------------------

@pytest.mark.parametrize(
    "hub,country,expected",
    [
        ("ATL", "US", "EXP-MFG-AIO-ATL-US-RG"),
        ("atl", "us", "EXP-MFG-AIO-ATL-US-RG"),
        ("LON", "GB", "EXP-MFG-AIO-LON-GB-RG"),
    ],
)
def test_build_resource_group(hub: str, country: str, expected: str) -> None:
    assert ArcStatusReader.build_resource_group(hub, country) == expected


# ---------------------------------------------------------------------------
# Endpoint tests: GET /api/devices/{device_name}/arc-status
# ---------------------------------------------------------------------------

def test_arc_status_returns_connected_status() -> None:
    client = build_arc_test_client()

    response = client.get("/api/devices/atl-azureiot-vm-k3s/arc-status")

    assert response.status_code == 200
    body = response.json()
    assert body["deviceName"] == "atl-azureiot-vm-k3s"
    assert body["resourceGroup"] == "EXP-MFG-AIO-ATL-US-RG"
    assert body["host"]["resourceType"] == "Microsoft.HybridCompute/machines"
    assert body["host"]["status"] == "Connected"
    assert body["vm"]["resourceType"] == "Microsoft.HybridCompute/machines"
    assert body["vm"]["status"] == "Connected"
    assert body["k8sCluster"]["resourceType"] == "Microsoft.Kubernetes/connectedClusters"
    assert body["k8sCluster"]["status"] == "Connected"


def test_arc_status_device_not_in_eventhouse_returns_404() -> None:
    client = build_arc_test_client()

    response = client.get("/api/devices/missing-vm-k3s/arc-status")

    assert response.status_code == 404
    assert "missing-vm-k3s" in response.json()["detail"]


def test_arc_status_eventhouse_failure_returns_502() -> None:
    client = build_arc_test_client()

    response = client.get("/api/devices/kusto-error-vm-k3s/arc-status")

    assert response.status_code == 502
    assert response.json()["detail"] == "Failed to fetch device status"


def test_arc_status_missing_country_returns_502() -> None:
    client = build_arc_test_client()

    response = client.get("/api/devices/no-country-vm-k3s/arc-status")

    assert response.status_code == 502
    assert "hub or country" in response.json()["detail"]


def test_arc_status_arm_not_found_returns_404() -> None:
    client = build_arc_test_client()

    response = client.get("/api/devices/arc-notfound-vm-k3s/arc-status")

    assert response.status_code == 404


def test_arc_status_arm_failure_returns_502() -> None:
    client = build_arc_test_client()

    response = client.get("/api/devices/arc-error-vm-k3s/arc-status")

    assert response.status_code == 502
    assert response.json()["detail"] == "Failed to fetch Arc status"


def test_arc_status_invalid_device_name_returns_400() -> None:
    client = build_arc_test_client()

    response = client.get("/api/devices/invalid_name/arc-status")

    assert response.status_code == 400
    assert response.json()["detail"] == "Invalid device name"
