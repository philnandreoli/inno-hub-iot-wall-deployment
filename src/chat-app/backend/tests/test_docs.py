import os

import pytest
from fastapi.testclient import TestClient
from unittest.mock import patch

from app.main import create_app


def _assert_docs_disabled(env: dict[str, str]) -> None:
    with patch.dict(os.environ, env, clear=False):
        app = create_app()
        client = TestClient(app, raise_server_exceptions=False)
        assert client.get("/docs").status_code == 404
        assert client.get("/redoc").status_code == 404
        assert client.get("/openapi.json").status_code == 404


@pytest.mark.parametrize(
    "env_value",
    ["false", "0", "no", "FALSE", "False"],
)
def test_docs_disabled_when_explicitly_falsy(env_value: str) -> None:
    _assert_docs_disabled({"ENABLE_DOCS": env_value})


def test_docs_disabled_by_default() -> None:
    # Ensure ENABLE_DOCS is absent so the default ("false") applies.
    original = os.environ.pop("ENABLE_DOCS", None)
    try:
        _assert_docs_disabled({})
    finally:
        if original is not None:
            os.environ["ENABLE_DOCS"] = original


@pytest.mark.parametrize(
    "env_value",
    ["true", "1", "yes", "TRUE", "True"],
)
def test_docs_enabled_when_explicitly_opted_in(env_value: str) -> None:
    with patch.dict(os.environ, {"ENABLE_DOCS": env_value}, clear=False):
        app = create_app()
        client = TestClient(app, raise_server_exceptions=False)
        assert client.get("/docs").status_code == 200
        assert client.get("/redoc").status_code == 200
        assert client.get("/openapi.json").status_code == 200
