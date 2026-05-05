import os
from dataclasses import dataclass

from dotenv import load_dotenv

load_dotenv()


@dataclass(frozen=True)
class Settings:
    azure_tenant_id: str
    azure_client_id: str
    azure_eventgrid_mqtt_host: str
    azure_eventgrid_mqtt_port: int
    azure_eventgrid_mqtt_client_id: str
    mqtt_qos: int
    mqtt_response_topic: str
    fabric_eventhouse_query_uri: str
    fabric_eventhouse_database: str
    fabric_eventhouse_query_retries: int
    applicationinsights_connection_string: str
    enable_docs: bool
    azure_subscription_id: str
    cors_allowed_origins: list[str]

    @classmethod
    def from_env(cls) -> "Settings":
        raw_cors = os.getenv("CORS_ALLOWED_ORIGINS", "").strip()
        cors_origins = [o.strip() for o in raw_cors.split(",") if o.strip()]

        return cls(
            azure_tenant_id=os.getenv("APP_AZURE_TENANT_ID", os.getenv("AZURE_TENANT_ID", "common")),
            azure_client_id=os.getenv("APP_AZURE_CLIENT_ID", os.getenv("AZURE_CLIENT_ID", "")).strip(),
            azure_eventgrid_mqtt_host=os.getenv("AZURE_EVENTGRID_MQTT_HOST", "").strip(),
            azure_eventgrid_mqtt_port=int(os.getenv("AZURE_EVENTGRID_MQTT_PORT", "8883")),
            azure_eventgrid_mqtt_client_id=os.getenv("AZURE_EVENTGRID_MQTT_CLIENT_ID", "").strip(),
            mqtt_qos=int(os.getenv("MQTT_QOS", "1")),
            mqtt_response_topic=os.getenv(
                "MQTT_RESPONSE_TOPIC",
                "azure-iot-operations/responses/beckhoff-controller",
            ).strip(),
            fabric_eventhouse_query_uri=os.getenv("FABRIC_EVENTHOUSE_QUERY_URI", "").strip(),
            fabric_eventhouse_database=os.getenv("FABRIC_EVENTHOUSE_DATABASE", "").strip(),
            fabric_eventhouse_query_retries=max(
                int(os.getenv("FABRIC_EVENTHOUSE_QUERY_RETRIES", "5")),
                1,
            ),
            applicationinsights_connection_string=os.getenv(
                "APPLICATIONINSIGHTS_CONNECTION_STRING", ""
            ).strip(),
            enable_docs=os.getenv("ENABLE_DOCS", "false").strip().lower() in ("true", "1", "yes"),
            azure_subscription_id=os.getenv("AZURE_SUBSCRIPTION_ID", "").strip(),
            cors_allowed_origins=cors_origins,
        )
