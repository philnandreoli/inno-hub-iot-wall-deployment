from .chat import router as chat_router
from .commands import router as commands_router
from .devices import router as devices_router
from .instances import router as instances_router

__all__ = ["chat_router", "devices_router", "commands_router", "instances_router"]
