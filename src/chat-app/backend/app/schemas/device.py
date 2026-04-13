from typing import Optional

from pydantic import BaseModel


class DeviceState(BaseModel):
    device_id: str
    online: Optional[bool] = None
    lamp: Optional[bool] = None
    fan: Optional[int] = None
    temperature: Optional[float] = None
    vibration: Optional[float] = None
    error_code: Optional[str] = None
    last_updated: Optional[str] = None
    raw: Optional[dict] = None


class DeviceListResponse(BaseModel):
    devices: list[str]
