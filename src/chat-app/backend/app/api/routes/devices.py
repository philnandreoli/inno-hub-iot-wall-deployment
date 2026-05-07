import logging
from datetime import datetime
from typing import Any, Annotated

from fastapi import APIRouter, Depends, HTTPException, Path, Query

from app.dependencies import get_arc_status_reader, get_publisher, get_status_reader, verify_token
from app.models.responses import (
    AllDevicesStatusResponse,
    ArcStatusResponse,
    CommandResponse,
    DevicesByHubResponse,
    DeviceStatusResponse,
    DeviceTelemetryResponse,
    SitesResponse,
)
from app.services.arc_status_reader import ArcStatusReader
from app.services.mqtt_publisher import MqttPublisher
from app.services.status_reader import EventhouseStatusReader
from app.validators import validate_date_range, validate_device_name, validate_timespan

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/devices", tags=["devices"])

ClaimsDep = Annotated[dict[str, Any], Depends(verify_token)]
PublisherDep = Annotated[MqttPublisher, Depends(get_publisher)]
StatusReaderDep = Annotated[EventhouseStatusReader, Depends(get_status_reader)]
ArcStatusReaderDep = Annotated[ArcStatusReader, Depends(get_arc_status_reader)]


def _publish_device_command(
    device_name: str,
    payload: dict[str, Any],
    message_expiry: int,
    publisher: MqttPublisher,
) -> dict[str, Any]:
    validated_device_name = validate_device_name(device_name)

    try:
        correlation_id = publisher.publish_command(
            device_name=validated_device_name,
            payload_data=payload,
            message_expiry=message_expiry,
        )
    except Exception as exc:  # noqa: BLE001
        logger.exception("Failed to publish device command for %s", validated_device_name)
        raise HTTPException(status_code=502, detail="Failed to execute device command") from exc

    return {
        "status": "published",
        "topic": f"/iotoperations/{validated_device_name}/command",
        "payload": payload,
        "qos": publisher.qos,
        "correlationData": correlation_id,
    }


@router.get("/{device_name}/commands/status", response_model=DeviceStatusResponse)
def get_device_status(
    device_name: str,
    reader: StatusReaderDep,
    _claims: ClaimsDep,
) -> dict[str, Any]:
    validated_device_name = validate_device_name(device_name)

    try:
        return reader.get_device_status(device_name=validated_device_name)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except Exception as exc:  # noqa: BLE001
        logger.exception("Failed to fetch device status for %s", validated_device_name)
        raise HTTPException(status_code=502, detail="Failed to fetch device status") from exc


@router.get("/{device_name}/telemetry", response_model=DeviceTelemetryResponse)
def get_device_telemetry(
    device_name: str,
    reader: StatusReaderDep,
    _claims: ClaimsDep,
    timespan: Annotated[str, Query(description="KQL timespan (e.g. 7d, 1h, 30min)")] = "7d",
    start_date: Annotated[
        datetime | None,
        Query(alias="startDate", description="Start timestamp (ISO 8601)")
    ] = None,
    end_date: Annotated[
        datetime | None,
        Query(alias="endDate", description="End timestamp (ISO 8601)")
    ] = None,
) -> dict[str, Any]:
    validated_device_name = validate_device_name(device_name)
    validated_start_date, validated_end_date = validate_date_range(start_date, end_date)

    # Only validate/use timespan when no date range is provided
    validated_timespan = validate_timespan(timespan) if validated_start_date is None else None

    try:
        return reader.get_device_telemetry(
            device_name=validated_device_name,
            timespan=validated_timespan,
            start_date=validated_start_date,
            end_date=validated_end_date,
        )
    except Exception as exc:  # noqa: BLE001
        logger.exception(
            "Failed to fetch telemetry for %s with timespan %s start_date=%s end_date=%s",
            validated_device_name,
            validated_timespan,
            validated_start_date,
            validated_end_date,
        )
        raise HTTPException(status_code=502, detail="Failed to fetch device telemetry") from exc


@router.get("/by-hub", response_model=DevicesByHubResponse)
def get_devices_by_hub(
    reader: StatusReaderDep,
    _claims: ClaimsDep,
) -> dict[str, Any]:
    try:
        return reader.get_devices_by_hub()
    except Exception as exc:  # noqa: BLE001
        logger.exception("Failed to fetch devices by hub")
        raise HTTPException(status_code=502, detail="Failed to fetch devices by hub") from exc


@router.get("/sites", response_model=SitesResponse)
def get_sites(
    reader: StatusReaderDep,
    _claims: ClaimsDep,
) -> dict[str, Any]:
    """Return all sites with their device names (IOT_INSTANCE_NAME)."""
    try:
        return reader.get_sites()
    except Exception as exc:  # noqa: BLE001
        logger.exception("Failed to fetch sites")
        raise HTTPException(status_code=502, detail="Failed to fetch sites") from exc


@router.get("/commands/status", response_model=AllDevicesStatusResponse)
def get_all_devices_status(
    reader: StatusReaderDep,
    _claims: ClaimsDep,
) -> dict[str, Any]:
    try:
        return reader.get_all_devices_status()
    except Exception as exc:  # noqa: BLE001
        logger.exception("Failed to fetch all devices status")
        raise HTTPException(status_code=502, detail="Failed to fetch all devices status") from exc



@router.get("/{device_name}/arc-status", response_model=ArcStatusResponse)
def get_device_arc_status(
    device_name: str,
    reader: StatusReaderDep,
    arc_reader: ArcStatusReaderDep,
    _claims: ClaimsDep,
) -> dict[str, Any]:
    validated_device_name = validate_device_name(device_name)

    hub: str | None = None
    country: str | None = None

    try:
        device_data = reader.get_device_status(validated_device_name)
        record = device_data.get("record", {})
        hub = record.get("hub") or record.get("Hub") or record.get("HUB")
        country = record.get("country") or record.get("Country") or record.get("COUNTRY")
    except LookupError:
        logger.info("Device %s not in Eventhouse, deriving hub from name", validated_device_name)
    except Exception as exc:  # noqa: BLE001
        logger.exception("Failed to fetch device status for %s", validated_device_name)

    # Fallback: derive hub from device name prefix (e.g. "dal-mtc2032-vm-k3s" → hub="dal")
    if not hub:
        dash_pos = validated_device_name.find("-")
        if dash_pos > 0:
            hub = validated_device_name[:dash_pos].upper()

    # Default country to US if not available
    if not country:
        country = "US"

    if not hub:
        raise HTTPException(
            status_code=502,
            detail="Cannot determine hub from device record or name",
        )

    try:
        return arc_reader.get_arc_status(validated_device_name, hub, country)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except Exception as exc:  # noqa: BLE001
        logger.exception("Failed to fetch Arc status for %s", validated_device_name)
        raise HTTPException(status_code=502, detail="Failed to fetch Arc status") from exc


@router.post("/{device_name}/commands/lamp/on", response_model=CommandResponse)
def lamp_on(
    device_name: str,
    publisher: PublisherDep,
    _claims: ClaimsDep,
) -> dict[str, Any]:
    return _publish_device_command(
        device_name=device_name,
        payload={"lamp": True},
        message_expiry=60,
        publisher=publisher,
    )


@router.post("/{device_name}/commands/lamp/off", response_model=CommandResponse)
def lamp_off(
    device_name: str,
    publisher: PublisherDep,
    _claims: ClaimsDep,
) -> dict[str, Any]:
    return _publish_device_command(
        device_name=device_name,
        payload={"lamp": False},
        message_expiry=5,
        publisher=publisher,
    )


@router.post("/{device_name}/commands/fan/on", response_model=CommandResponse)
def fan_on(
    device_name: str,
    publisher: PublisherDep,
    _claims: ClaimsDep,
) -> dict[str, Any]:
    return _publish_device_command(
        device_name=device_name,
        payload={"fan": 32000},
        message_expiry=60,
        publisher=publisher,
    )


@router.post("/{device_name}/commands/fan/off", response_model=CommandResponse)
def fan_off(
    device_name: str,
    publisher: PublisherDep,
    _claims: ClaimsDep,
) -> dict[str, Any]:
    return _publish_device_command(
        device_name=device_name,
        payload={"fan": 0},
        message_expiry=5,
        publisher=publisher,
    )


@router.post("/{device_name}/commands/blinkpattern/{blink_pattern_number}", response_model=CommandResponse)
def blink_pattern(
    device_name: str,
    publisher: PublisherDep,
    _claims: ClaimsDep,
    blink_pattern_number: int = Path(..., ge=0, le=6),
) -> dict[str, Any]:
    return _publish_device_command(
        device_name=device_name,
        payload={"blinkPattern": blink_pattern_number},
        message_expiry=5,
        publisher=publisher,
    )
