from functools import lru_cache
from typing import Any

from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials

from app.config import Settings
from app.security import TokenVerifier, bearer_scheme
from app.services.azure_vm_status import AzureVmStatusReader
from app.services.mqtt_publisher import MqttPublisher
from app.services.status_reader import EventhouseStatusReader


@lru_cache
def get_settings() -> Settings:
    return Settings.from_env()


@lru_cache
def get_publisher() -> MqttPublisher:
    return MqttPublisher(settings=get_settings())


@lru_cache
def get_status_reader() -> EventhouseStatusReader:
    return EventhouseStatusReader(settings=get_settings())


@lru_cache
def get_azure_vm_status_reader() -> AzureVmStatusReader:
    return AzureVmStatusReader(settings=get_settings())


@lru_cache
def get_token_verifier() -> TokenVerifier:
    return TokenVerifier(settings=get_settings())


async def verify_token(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> dict[str, Any]:
    verifier = get_token_verifier()
    return await verifier.verify(credentials)
