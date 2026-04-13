import logging

from fastapi import APIRouter, Depends, HTTPException, status

from app.schemas.command import CommandRequest, CommandResponse
from app.services.eventgrid_service import EventGridService, get_eventgrid_service

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api", tags=["commands"])


@router.post("/commands/{deviceId}", response_model=CommandResponse)
async def publish_command(
    deviceId: str,
    payload: CommandRequest,
    service: EventGridService = Depends(get_eventgrid_service),
) -> CommandResponse:
    if payload.action == "lamp" and not isinstance(payload.value, bool):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                detail="For action 'lamp', value must be boolean",
            )
    if payload.action == "fan":
        if isinstance(payload.value, bool) or not isinstance(payload.value, int):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                detail="For action 'fan', value must be integer",
            )
        if payload.value < 0 or payload.value > 32000:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                detail="For action 'fan', value must be between 0 and 32000",
            )

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
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=str(exc),
        ) from exc
    except Exception as exc:
        logger.exception("Failed to publish command for deviceId=%s", deviceId)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Failed to publish command",
        ) from exc
