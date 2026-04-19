import json
import socket
import ssl
import threading
import time
import uuid

import paho.mqtt.client as mqtt
from azure.identity import DefaultAzureCredential
from paho.mqtt.packettypes import PacketTypes
from paho.mqtt.properties import Properties

from app.config import Settings
from app.validators import validate_device_name


class MqttPublisher:
    def __init__(self, settings: Settings) -> None:
        if not settings.azure_eventgrid_mqtt_host:
            raise RuntimeError(
                "Missing required environment variable(s): AZURE_EVENTGRID_MQTT_HOST"
            )

        self.host = settings.azure_eventgrid_mqtt_host
        self.port = settings.azure_eventgrid_mqtt_port
        self.qos = settings.mqtt_qos
        self.response_topic = settings.mqtt_response_topic
        self.token_scope = "https://eventgrid.azure.net/.default"
        self._access_token = ""
        self._token_expires_on = 0

        self.credential = DefaultAzureCredential()
        stable_client_id = settings.azure_eventgrid_mqtt_client_id or self._default_client_id()

        self.client = mqtt.Client(
            callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
            client_id=stable_client_id,
            protocol=mqtt.MQTTv5,
        )
        self.client.tls_set(tls_version=ssl.PROTOCOL_TLS_CLIENT)
        self.client.tls_insecure_set(False)
        self.client.reconnect_delay_set(min_delay=1, max_delay=30)

        self._connected = threading.Event()
        self._last_error: str | None = None
        self._connect_lock = threading.Lock()
        self._loop_started = False
        self._reconnect_thread: threading.Thread | None = None

        self.client.on_connect = self._on_connect
        self.client.on_disconnect = self._on_disconnect

    def _default_client_id(self) -> str:
        host = socket.gethostname().lower().replace("_", "-")
        return f"iot-command-api-{host}"[:64]

    def _build_connect_properties(self) -> Properties:
        connect_properties = Properties(PacketTypes.CONNECT)
        connect_properties.AuthenticationMethod = "OAUTH2-JWT"
        connect_properties.AuthenticationData = self._access_token.encode("utf-8")
        return connect_properties

    def _refresh_access_token(self) -> bool:
        if self._token_expires_on - int(time.time()) > 120:
            return False

        token = self.credential.get_token(self.token_scope)
        self._access_token = token.token
        self._token_expires_on = token.expires_on
        return True

    def _on_connect(self, _client, _userdata, _flags, reason_code, _properties):
        code = getattr(reason_code, "value", reason_code)
        if code == 0:
            self._connected.set()
            self._last_error = None
        else:
            self._last_error = f"MQTT connect failed with reason code {code}"

    def _on_disconnect(self, _client, _userdata, _disconnect_flags, reason_code, _properties):
        self._connected.clear()
        code = getattr(reason_code, "value", reason_code)
        if code != 0:
            self._last_error = f"MQTT disconnected with reason code {code}"
            self._start_reconnect_worker()

    def _start_reconnect_worker(self) -> None:
        if self._reconnect_thread and self._reconnect_thread.is_alive():
            return

        self._reconnect_thread = threading.Thread(target=self._reconnect_worker, daemon=True)
        self._reconnect_thread.start()

    def _reconnect_worker(self) -> None:
        for attempt in range(1, 6):
            try:
                self.connect(force_reconnect=True)
                if self._connected.is_set():
                    return
            except Exception as exc:  # noqa: BLE001
                self._last_error = f"Reconnect attempt {attempt} failed: {exc}"

            time.sleep(min(2**attempt, 30))

    def _start_loop_if_needed(self) -> None:
        if self._loop_started:
            return
        self.client.loop_start()
        self._loop_started = True

    def connect(self, force_reconnect: bool = False) -> None:
        if self._connected.is_set() and not force_reconnect:
            return

        with self._connect_lock:
            if self._connected.is_set() and not force_reconnect:
                return

            self._refresh_access_token()
            self.client.connect(
                self.host,
                self.port,
                keepalive=60,
                clean_start=mqtt.MQTT_CLEAN_START_FIRST_ONLY,
                properties=self._build_connect_properties(),
            )
            self._start_loop_if_needed()

        if not self._connected.wait(timeout=10):
            error_detail = self._last_error or "Timeout waiting for MQTT connection"
            raise RuntimeError(error_detail)

    def publish_command(
        self,
        device_name: str,
        payload_data: dict,
        message_expiry: int = 60,
    ) -> str:
        self.connect()
        validated_device_name = validate_device_name(device_name)
        topic = f"/iotoperations/{validated_device_name}/command"
        payload = json.dumps(payload_data)
        correlation_uuid = uuid.uuid4()

        publish_properties = Properties(PacketTypes.PUBLISH)
        publish_properties.PayloadFormatIndicator = 1
        publish_properties.ContentType = "application/json"
        publish_properties.CorrelationData = correlation_uuid.bytes
        publish_properties.MessageExpiryInterval = message_expiry
        publish_properties.ResponseTopic = self.response_topic
        publish_properties.UserProperty = [
            (
                "__srcId",
                self.client._client_id.decode("utf-8")
                if isinstance(self.client._client_id, bytes)
                else self.client._client_id,
            ),
        ]

        result = self.client.publish(
            topic,
            payload=payload,
            qos=self.qos,
            properties=publish_properties,
        )
        result.wait_for_publish(timeout=5)

        if result.rc == mqtt.MQTT_ERR_NO_CONN:
            self.connect(force_reconnect=True)
            result = self.client.publish(
                topic,
                payload=payload,
                qos=self.qos,
                properties=publish_properties,
            )
            result.wait_for_publish(timeout=5)

        if result.rc != mqtt.MQTT_ERR_SUCCESS:
            raise RuntimeError(f"Failed to publish MQTT message: {mqtt.error_string(result.rc)}")

        return str(correlation_uuid)
