import os
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient

from app.main import create_app


def build_cors_client(cors_origins: str) -> TestClient:
    with patch.dict(os.environ, {"CORS_ALLOWED_ORIGINS": cors_origins}, clear=False):
        app = create_app()
        return TestClient(app, raise_server_exceptions=False)


@pytest.mark.parametrize(
    "cors_env,request_origin,expected_header",
    [
        # Single origin configured — matching request should get the header
        ("http://localhost:3000", "http://localhost:3000", "http://localhost:3000"),
        # Multiple comma-separated origins — second origin should match
        (
            "http://localhost:3000,http://localhost:5173",
            "http://localhost:5173",
            "http://localhost:5173",
        ),
    ],
)
def test_cors_header_present_for_allowed_origin(
    cors_env: str, request_origin: str, expected_header: str
) -> None:
    client = build_cors_client(cors_env)
    response = client.get("/health", headers={"Origin": request_origin})
    assert response.headers.get("access-control-allow-origin") == expected_header


def test_cors_header_absent_when_no_origins_configured() -> None:
    env = {"CORS_ALLOWED_ORIGINS": ""}
    with patch.dict(os.environ, env, clear=False):
        app = create_app()
        client = TestClient(app, raise_server_exceptions=False)
        response = client.get("/health", headers={"Origin": "http://localhost:3000"})
    assert "access-control-allow-origin" not in response.headers


def test_cors_preflight_returns_200_for_allowed_origin() -> None:
    client = build_cors_client("http://localhost:3000")
    response = client.options(
        "/health",
        headers={
            "Origin": "http://localhost:3000",
            "Access-Control-Request-Method": "GET",
        },
    )
    assert response.status_code == 200
    assert response.headers.get("access-control-allow-origin") == "http://localhost:3000"


def test_settings_parses_multiple_cors_origins() -> None:
    from app.config import Settings

    with patch.dict(
        os.environ,
        {"CORS_ALLOWED_ORIGINS": "http://localhost:3000, http://localhost:5173"},
        clear=False,
    ):
        settings = Settings.from_env()

    assert settings.cors_allowed_origins == ["http://localhost:3000", "http://localhost:5173"]


def test_settings_empty_cors_origins_when_not_set() -> None:
    from app.config import Settings

    with patch.dict(os.environ):
        os.environ.pop("CORS_ALLOWED_ORIGINS", None)
        settings = Settings.from_env()

    assert settings.cors_allowed_origins == []
