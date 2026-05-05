from fastapi import FastAPI

from app.api.routes.chat import router as chat_router
from app.api.routes.devices import router as devices_router
from app.api.routes.health import router as health_router
from app.config import Settings
from app.telemetry import configure_telemetry

openapi_tags = [
    {"name": "health", "description": "Service health endpoints."},
    {"name": "devices", "description": "Device command and status endpoints."},
    {"name": "chat", "description": "Natural-language device command endpoints."},
]


def create_app() -> FastAPI:
    configure_telemetry()
    settings = Settings.from_env()
    docs_kwargs = (
        {"openapi_tags": openapi_tags}
        if settings.enable_docs
        else {"docs_url": None, "redoc_url": None, "openapi_url": None}
    )
    app = FastAPI(title="IoT Device Command API", **docs_kwargs)
    app.include_router(health_router)
    app.include_router(devices_router)
    app.include_router(chat_router)
    return app


app = create_app()
