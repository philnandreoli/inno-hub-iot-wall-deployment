import logging

from fastapi import APIRouter, Depends, HTTPException, status

from app.schemas.command import CommandRequest, CommandResponse
from app.services.eventgrid_service import EventGridMQTTService, get_eventgrid_service

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api", tags=["commands"])


@router.post("/commands/{deviceId}", response_model=CommandResponse)
async def publish_command(
    deviceId: str,
    payload: CommandRequest,
    service: EventGridMQTTService = Depends(get_eventgrid_service),
) -> CommandResponse:
    try:
        await service.publish_command(deviceId, payload.action, payload.value)
        return CommandResponse(
            success=True,
            device_id=deviceId,
            action=payload.action,
            message="Command published successfully",
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=str(exc),
        ) from exc
    except Exception as exc:
        logger.exception("Failed to publish command for deviceId=%s", deviceId)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Failed to publish command",
        ) from exc
