"""
IoT Wall Chat App – FastAPI backend entrypoint.

Start locally:
    uvicorn app.main:app --reload --port 5000
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(
    title="IoT Wall Chat App API",
    description="LLM-powered device operations chat backend for Azure IoT Operations.",
    version="0.1.0",
)

# Allow the Vite dev server (port 3000) and production front-end to call this API.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://127.0.0.1:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health", tags=["ops"])
async def health_check() -> dict:
    """Liveness probe – returns service status."""
    return {"status": "ok", "service": "iot-wall-chat-api"}


@app.get("/", tags=["ops"])
async def root() -> dict:
    """Root redirect hint."""
    return {"message": "IoT Wall Chat API. See /docs for the OpenAPI interface."}
