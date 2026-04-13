import logging

from fastapi import APIRouter, Depends, HTTPException, status

from app.schemas.instance import InstanceListResponse
from app.services.instances_service import InstancesService, get_instances_service

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api", tags=["instances"])


@router.get("/instances", response_model=InstanceListResponse)
async def list_instances(
    service: InstancesService = Depends(get_instances_service),
) -> InstanceListResponse:
    try:
        instances = await service.list_instances()
        return InstanceListResponse(instances=instances)
    except Exception as exc:
        logger.exception("Failed to list AIO instances")
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Failed to retrieve IoT Operations instances",
        ) from exc
