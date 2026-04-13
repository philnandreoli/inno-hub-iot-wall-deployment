from .chat import ChatRequest, ChatResponse
from .command import CommandRequest, CommandResponse, FanCommand, LampCommand
from .device import DeviceListResponse, DeviceState
from .instance import AioInstance, InstanceListResponse

__all__ = [
    "ChatRequest",
    "ChatResponse",
    "LampCommand",
    "FanCommand",
    "CommandRequest",
    "CommandResponse",
    "DeviceState",
    "DeviceListResponse",
    "AioInstance",
    "InstanceListResponse",
]
