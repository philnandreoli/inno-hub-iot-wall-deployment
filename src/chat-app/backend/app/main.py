from fastapi import FastAPI

from app.api.routes.devices import router as devices_router
from app.api.routes.health import router as health_router
from app.telemetry import configure_telemetry

openapi_tags = [
    {"name": "health", "description": "Service health endpoints."},
    {"name": "devices", "description": "Device command and status endpoints."},
]


def create_app() -> FastAPI:
    configure_telemetry()
    app = FastAPI(title="IoT Device Command API", openapi_tags=openapi_tags)
    app.include_router(health_router)
    app.include_router(devices_router)
    return app


app = create_app()
