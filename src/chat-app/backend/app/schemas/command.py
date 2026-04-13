from typing import Literal, Union

from pydantic import BaseModel, field_validator


class LampCommand(BaseModel):
    lamp: bool


class FanCommand(BaseModel):
    fan: int

    @field_validator("fan")
    @classmethod
    def validate_fan_range(cls, value: int) -> int:
        if value < 0 or value > 32000:
            raise ValueError("fan value must be between 0 and 32000")
        return value


class CommandRequest(BaseModel):
    action: Literal["lamp", "fan"]
    value: Union[bool, int]


class CommandResponse(BaseModel):
    success: bool
    device_id: str
    action: str
    message: str
