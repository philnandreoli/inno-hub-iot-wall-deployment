import asyncio
import json
import logging
import os
import ssl
import threading
from functools import lru_cache
from typing import Union

import paho.mqtt.client as mqtt

from app.config import settings
from app.services.auth import get_credential

logger = logging.getLogger(__name__)

# Scope required to obtain an Azure AD token for EventGrid MQTT broker authentication.
EVENTGRID_SCOPE = "https://eventgrid.azure.net/.default"


class EventGridMQTTService:
    """Publishes device commands to Azure Event Grid via the MQTT broker endpoint.

    Authentication uses DefaultAzureCredential (Managed Identity in Azure,
    Azure CLI / environment credentials in local dev).  The access token is
    obtained for the EventGrid scope and passed as the MQTT password — no
    connection strings or keys are required.

    MQTT connection parameters:
        hostname : EVENTGRID_MQTT_HOSTNAME  (e.g. <namespace>.<region>-1.ts.eventgrid.azure.net)
        port     : EVENTGRID_MQTT_PORT      (default 8883 / TLS)
        topic    : iotoperations/<instanceName>/commands/<deviceId>
    """

    def __init__(self) -> None:
        if not settings.eventgrid_mqtt_hostname:
            raise ValueError("EVENTGRID_MQTT_HOSTNAME is not configured")

        self.hostname: str = settings.eventgrid_mqtt_hostname
        self.port: int = settings.eventgrid_mqtt_port
        self._base_topic: str = f"iotoperations/{settings.instance_name}/commands"
        self._credential = get_credential()

    # ------------------------------------------------------------------
    # Public interface
    # ------------------------------------------------------------------

    async def publish_command(
        self, device_id: str, action: str, value: Union[bool, int]
    ) -> bool:
        """Validate and publish a device command via MQTT.

        Returns True on success; raises on validation or publish failure.
        """
        payload = self._validate_and_build_payload(action=action, value=value)
        topic = f"{self._base_topic}/{device_id}"
        message = json.dumps(payload)

        logger.info(
            "Publishing MQTT command device_id=%s action=%s topic=%s",
            device_id,
            action,
            topic,
        )
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(None, self._publish_sync, topic, message)
        return True

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _get_access_token(self) -> str:
        """Obtain a short-lived Azure AD token for the EventGrid MQTT scope."""
        token = self._credential.get_token(EVENTGRID_SCOPE)
        return token.token

    def _publish_sync(self, topic: str, message: str) -> None:
        """Synchronous MQTT publish executed in a thread-pool executor."""
        access_token = self._get_access_token()
        tls_context = ssl.create_default_context()

        connected_event = threading.Event()
        published_event = threading.Event()
        errors: list[Exception] = []

        def on_connect(
            client: mqtt.Client,
            userdata: object,
            flags: mqtt.ConnectFlags,
            reason_code: mqtt.ReasonCode,
            properties: mqtt.Properties,
        ) -> None:
            if reason_code == 0:
                logger.debug("MQTT connected to %s", self.hostname)
            else:
                errors.append(
                    ConnectionError(f"MQTT connection refused: reason_code={reason_code}")
                )
            connected_event.set()

        def on_publish(
            client: mqtt.Client,
            userdata: object,
            mid: int,
            reason_code: mqtt.ReasonCode,
            properties: mqtt.Properties,
        ) -> None:
            logger.debug("MQTT publish acknowledged mid=%s", mid)
            published_event.set()

        client = mqtt.Client(
            callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
            protocol=mqtt.MQTTv5,
            client_id=f"iot-chat-{os.getpid()}",
        )
        # Azure Event Grid MQTT broker: use hostname as username, AD token as password.
        client.username_pw_set(username=self.hostname, password=access_token)
        client.tls_set_context(tls_context)
        client.on_connect = on_connect
        client.on_publish = on_publish

        client.connect(self.hostname, self.port, keepalive=30)
        client.loop_start()
        try:
            if not connected_event.wait(timeout=15):
                raise TimeoutError("MQTT connection timed out after 15 s")
            if errors:
                raise errors[0]

            result = client.publish(topic, message, qos=1)
            if result.rc != mqtt.MQTT_ERR_SUCCESS:
                raise RuntimeError(f"MQTT publish enqueue failed: rc={result.rc}")

            if not published_event.wait(timeout=15):
                raise TimeoutError("MQTT publish acknowledgement timed out after 15 s")
        finally:
            client.loop_stop()
            client.disconnect()

    @staticmethod
    def _validate_and_build_payload(action: str, value: Union[bool, int]) -> dict:
        if action == "lamp":
            if not isinstance(value, bool):
                raise ValueError("Lamp value must be a boolean")
            return {"lamp": value}
        if action == "fan":
            # bool is a subclass of int in Python, so explicitly reject booleans first
            if isinstance(value, bool) or not isinstance(value, int):
                raise ValueError("Fan value must be a non-boolean integer")
            if value < 0 or value > 32000:
                raise ValueError("Fan value must be between 0 and 32000")
            return {"fan": value}
        raise ValueError(f"Unsupported action: {action!r}")


@lru_cache(maxsize=1)
def get_eventgrid_service() -> EventGridMQTTService:
    return EventGridMQTTService()
