"""Pydantic response models for all API endpoints.

These models define the strict API contract: field names, types, and
descriptions that appear in the OpenAPI/Swagger schema. Every route
uses a ``response_model`` pointing to one of these classes so that:

- OpenAPI docs display accurate schemas with field descriptions.
- FastAPI validates outgoing responses (catches backend bugs early).
- Frontend consumers rely on stable camelCase field names.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Health
# ---------------------------------------------------------------------------

class HealthResponse(BaseModel):
    """Response for GET /health."""

    status: str = Field(description="Service status indicator (e.g. 'ok')")


# ---------------------------------------------------------------------------
# Command (MQTT publish result)
# ---------------------------------------------------------------------------

class CommandResponse(BaseModel):
    """Response for all POST /commands/* endpoints."""

    status: str = Field(description="Publish status (always 'published' on success)")
    topic: str = Field(description="MQTT topic the command was sent to")
    payload: dict[str, Any] = Field(description="Command payload sent to the device")
    qos: int = Field(description="MQTT QoS level used for publishing")
    correlationData: str = Field(description="Correlation ID for tracking the published message")


# ---------------------------------------------------------------------------
# Device status
# ---------------------------------------------------------------------------

class DeviceStatusResponse(BaseModel):
    """Response for GET /{device_name}/commands/status."""

    deviceName: str = Field(description="Canonical device name (e.g. 'atl-azureiot-vm-k3s')")
    source: str = Field(description="Data source identifier (e.g. 'fabric-eventhouse')")
    record: dict[str, Any] = Field(
        description="Latest normalized status record from Eventhouse (all fields camelCase)"
    )


# ---------------------------------------------------------------------------
# All-devices status
# ---------------------------------------------------------------------------

class AllDevicesStatusResponse(BaseModel):
    """Response for GET /commands/status."""

    source: str = Field(description="Data source identifier")
    count: int = Field(description="Number of device records returned")
    devices: list[dict[str, Any]] = Field(
        description="List of normalized device status records (all fields camelCase)"
    )


# ---------------------------------------------------------------------------
# Devices by hub
# ---------------------------------------------------------------------------

class DevicesByHubResponse(BaseModel):
    """Response for GET /by-hub."""

    source: str = Field(description="Data source identifier")
    count: int = Field(description="Number of devices returned")
    devicesByHub: list[dict[str, Any]] = Field(
        description="List of device-to-hub mapping records"
    )


class SitesResponse(BaseModel):
    """Response for GET /sites."""

    source: str = Field(description="Data source identifier")
    count: int = Field(description="Number of sites returned")
    sites: list[dict[str, Any]] = Field(
        description="List of site records with NAME, CODE, IOT_INSTANCE_NAME, etc."
    )


# ---------------------------------------------------------------------------
# Telemetry
# ---------------------------------------------------------------------------

class TelemetryMeasurement(BaseModel):
    """A single IoT telemetry measurement row."""

    iotInstanceName: str | None = Field(None, description="IoT instance that produced the reading")
    tag: str | None = Field(None, description="Measurement tag (e.g. 'temperature')")
    timestamp: str | None = Field(None, description="Measurement timestamp (ISO 8601)")
    value_long: float | None = Field(None, description="Numeric measurement value")
    value_bool: bool | None = Field(None, description="Boolean measurement value")


class DeviceTelemetryResponse(BaseModel):
    """Response for GET /{device_name}/telemetry."""

    deviceName: str = Field(description="Device name the telemetry belongs to")
    timespan: str | None = Field(None, description="KQL timespan used for the query (e.g. '7d')")
    startDate: datetime | None = Field(None, description="Query start timestamp (ISO 8601)")
    endDate: datetime | None = Field(None, description="Query end timestamp (ISO 8601)")
    source: str = Field(description="Data source identifier")
    count: int = Field(description="Number of measurement rows returned")
    measurements: list[TelemetryMeasurement] = Field(
        description="Ordered list of telemetry measurement rows"
    )


# ---------------------------------------------------------------------------
# Arc status
# ---------------------------------------------------------------------------

class ArcResource(BaseModel):
    """A single Azure Arc-enrolled resource and its connectivity status."""

    resourceName: str = Field(description="Azure resource name")
    resourceType: str = Field(description="Azure resource type (e.g. 'Microsoft.HybridCompute/machines')")
    status: str = Field(description="Connectivity status reported by Azure ARM")


class ArcStatusResponse(BaseModel):
    """Response for GET /{device_name}/arc-status."""

    deviceName: str = Field(description="Device name whose Arc status is being reported")
    resourceGroup: str = Field(description="Azure resource group the device lives in")
    host: ArcResource = Field(description="HybridCompute status for the bare-metal host")
    vm: ArcResource = Field(description="HybridCompute status for the VM")
    k8sCluster: ArcResource = Field(description="ConnectedCluster status for the K8s cluster")


# ---------------------------------------------------------------------------
# Chat (natural-language device commands)
# ---------------------------------------------------------------------------

class ChatRequest(BaseModel):
    """Request body for POST /api/chat."""

    sessionId: str = Field(description="Browser-tab-scoped session identifier (UUID)")
    message: str = Field(description="Natural-language message from the operator")


class PendingAction(BaseModel):
    """A write command that has been parsed but not yet executed."""

    functionName: str = Field(description="Internal tool name (e.g. 'set_lamp_state')")
    arguments: dict[str, Any] = Field(description="Parsed arguments for the function")
    description: str = Field(
        description="Human-readable description of the action (e.g. 'Turn lamp ON on atl-azureiot-vm-k3s')"
    )


class ChatResponse(BaseModel):
    """Response for POST /api/chat and POST /api/chat/confirm."""

    message: str = Field(description="Assistant's reply to display in the chat panel")
    pendingAction: PendingAction | None = Field(
        None,
        description=(
            "Set when a write command is ready for confirmation. "
            "Null for read-only queries or after a command is resolved."
        ),
    )


class ChatConfirmRequest(BaseModel):
    """Request body for POST /api/chat/confirm and POST /api/chat/cancel."""

    sessionId: str = Field(description="Session identifier matching the pending action")
