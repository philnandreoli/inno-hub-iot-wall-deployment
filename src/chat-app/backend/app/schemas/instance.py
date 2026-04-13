from typing import Optional

from pydantic import BaseModel


class AioInstance(BaseModel):
    name: str
    resource_group: str
    subscription_id: str
    location: str
    description: Optional[str] = None


class InstanceListResponse(BaseModel):
    instances: list[AioInstance]
