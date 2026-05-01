import logging
from datetime import datetime
from typing import Any, Annotated

from fastapi import APIRouter, Depends, HTTPException, Path, Query

from app.dependencies import get_azure_vm_status_reader, get_publisher, get_status_reader, verify_token
from app.services.azure_vm_status import AzureVmStatusReader
from app.services.mqtt_publisher import MqttPublisher
from app.services.status_reader import EventhouseStatusReader
from app.validators import validate_date_range, validate_device_name, validate_timespan

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/devices", tags=["devices"])

ClaimsDep = Annotated[dict[str, Any], Depends(verify_token)]
PublisherDep = Annotated[MqttPublisher, Depends(get_publisher)]
StatusReaderDep = Annotated[EventhouseStatusReader, Depends(get_status_reader)]
AzureVmStatusReaderDep = Annotated[AzureVmStatusReader, Depends(get_azure_vm_status_reader)]


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


@router.get("/{device_name}/azure-status")
def get_device_azure_status(
    device_name: str,
    reader: StatusReaderDep,
    azure_vm_reader: AzureVmStatusReaderDep,
    _claims: ClaimsDep,
) -> dict[str, Any]:
    validated_device_name = validate_device_name(device_name)

    # Fetch the device status record to extract a VM identifier.
    # If the device is not found or the query fails, fall back to an empty record so
    # the Azure reader can still return "Not Implemented" gracefully.
    try:
        status = reader.get_device_status(device_name=validated_device_name)
        record: dict[str, Any] = status.get("record") or {}
    except LookupError:
        record = {}
    except Exception:  # noqa: BLE001
        logger.exception("Failed to fetch status record for azure-status check on %s", validated_device_name)
        record = {}

    try:
        return azure_vm_reader.get_vm_status(device_name=validated_device_name, record=record)
    except Exception as exc:  # noqa: BLE001
        logger.exception("Failed to fetch Azure VM status for %s", validated_device_name)
        raise HTTPException(status_code=502, detail="Failed to fetch Azure VM status") from exc


@router.get("/{device_name}/commands/status")
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


@router.get("/{device_name}/telemetry")
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


@router.get("/by-hub")
def get_devices_by_hub(
    reader: StatusReaderDep,
    _claims: ClaimsDep,
) -> dict[str, Any]:
    try:
        return reader.get_devices_by_hub()
    except Exception as exc:  # noqa: BLE001
        logger.exception("Failed to fetch devices by hub")
        raise HTTPException(status_code=502, detail="Failed to fetch devices by hub") from exc


@router.get("/commands/status")
def get_all_devices_status(
    reader: StatusReaderDep,
    _claims: ClaimsDep,
) -> dict[str, Any]:
    try:
        return reader.get_all_devices_status()
    except Exception as exc:  # noqa: BLE001
        logger.exception("Failed to fetch all devices status")
        raise HTTPException(status_code=502, detail="Failed to fetch all devices status") from exc


@router.post("/{device_name}/commands/lamp/on")
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


@router.post("/{device_name}/commands/lamp/off")
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


@router.post("/{device_name}/commands/fan/on")
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


@router.post("/{device_name}/commands/fan/off")
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


@router.post("/{device_name}/commands/blinkpattern/{blink_pattern_number}")
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
