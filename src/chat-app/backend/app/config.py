from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    azure_openai_endpoint: str = ""
    azure_openai_deployment: str = "gpt-4o"
    eventhouse_mcp_endpoint: str = ""
    # Azure Event Grid MQTT broker settings
    eventgrid_mqtt_hostname: str = ""
    eventgrid_mqtt_port: int = 8883
    # Redis cache
    redis_url: str = "redis://localhost:6379"
    # Device state cache TTL
    state_cache_ttl_seconds: int = 15
    # Optional: comma-separated Azure subscription IDs to search for AIO instances.
    # If empty, all subscriptions accessible to the credential are searched.
    azure_subscription_ids: str = ""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()
