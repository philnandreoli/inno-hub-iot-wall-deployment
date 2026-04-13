from typing import Literal, Union

from pydantic import BaseModel, field_validator, model_validator


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

    @model_validator(mode="after")
    def validate_action_value(self) -> "CommandRequest":
        if self.action == "lamp" and not isinstance(self.value, bool):
            raise ValueError("For action 'lamp', value must be a boolean")
        if self.action == "fan":
            # bool is a subclass of int in Python, so explicitly reject booleans
            if isinstance(self.value, bool) or not isinstance(self.value, int):
                raise ValueError("For action 'fan', value must be a non-boolean integer")
            if self.value < 0 or self.value > 32000:
                raise ValueError("For action 'fan', value must be between 0 and 32000")
        return self


class CommandResponse(BaseModel):
    success: bool
    device_id: str
    action: str
    message: str
