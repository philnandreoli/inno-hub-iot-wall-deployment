import logging
from functools import lru_cache
from typing import Union

from azure.core.credentials import AzureKeyCredential
from azure.core.messaging import CloudEvent
from azure.eventgrid import EventGridPublisherClient

from app.config import settings
from app.services.auth import get_credential

logger = logging.getLogger(__name__)


class EventGridService:
    def __init__(self):
        if not settings.eventgrid_endpoint:
            raise ValueError("EVENTGRID_ENDPOINT is not configured")

        credential = get_credential()
        try:
            self.client = EventGridPublisherClient(
                endpoint=settings.eventgrid_endpoint,
                credential=credential,
            )
        except Exception:
            if not settings.eventgrid_key:
                raise
            self.client = EventGridPublisherClient(
                endpoint=settings.eventgrid_endpoint,
                credential=AzureKeyCredential(settings.eventgrid_key),
            )
        self.topic_path = f"/iotoperations/{settings.instance_name}/commands"

    async def publish_command(
        self, device_id: str, action: str, value: Union[bool, int]
    ) -> bool:
        payload = self._validate_and_build_payload(action=action, value=value)
        event = CloudEvent(
            source=f"/chat-app/{device_id}",
            type="com.iotoperations.device.command",
            data=payload,
        )
        event["subject"] = self.topic_path
        logger.info("Publishing command for device_id=%s action=%s", device_id, action)
        self.client.send([event])
        return True

    @staticmethod
    def _validate_and_build_payload(action: str, value: Union[bool, int]) -> dict:
        if action == "lamp":
            if not isinstance(value, bool):
                raise ValueError("Lamp value must be a boolean")
            return {"lamp": value}
        if action == "fan":
            if isinstance(value, bool) or not isinstance(value, int):
                raise ValueError("Fan value must be an integer")
            if value < 0 or value > 32000:
                raise ValueError("Fan value must be between 0 and 32000")
            return {"fan": value}
        raise ValueError("Unsupported action")


@lru_cache(maxsize=1)
def get_eventgrid_service() -> EventGridService:
    return EventGridService()
