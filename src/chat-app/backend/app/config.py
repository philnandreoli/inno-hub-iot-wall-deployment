from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    azure_openai_endpoint: str = ""
    azure_openai_deployment: str = "gpt-4o"
    eventhouse_mcp_endpoint: str = ""
    eventgrid_endpoint: str = ""
    eventgrid_key: str = ""
    instance_name: str = "default"
    state_cache_ttl_seconds: int = 15

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()
