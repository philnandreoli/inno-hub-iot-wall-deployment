import logging

from fastapi import APIRouter, Depends, HTTPException, status

from app.schemas.device import DeviceListResponse, DeviceState
from app.services.device_state import DeviceStateService, get_device_state_service

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api", tags=["devices"])


@router.get("/devices", response_model=DeviceListResponse)
async def get_devices(
    service: DeviceStateService = Depends(get_device_state_service),
) -> DeviceListResponse:
    try:
        devices = await service.get_devices()
        return DeviceListResponse(devices=devices)
    except Exception as exc:
        logger.exception("Failed to fetch devices")
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Failed to fetch devices",
        ) from exc


@router.get("/device-state/{deviceId}", response_model=DeviceState)
async def get_device_state(
    deviceId: str,
    service: DeviceStateService = Depends(get_device_state_service),
) -> DeviceState:
    if not deviceId:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="deviceId is required",
        )
    try:
        return await service.get_cached_device_state(deviceId)
    except Exception as exc:
        logger.exception("Failed to fetch device state for deviceId=%s", deviceId)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Failed to fetch device state",
        ) from exc
