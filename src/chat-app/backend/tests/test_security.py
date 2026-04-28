import time
from typing import Any
from unittest.mock import patch

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric.rsa import RSAPrivateKey, RSAPublicKey
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials

from app.config import Settings
from app.security import TokenVerifier

TENANT_ID = "test-tenant-id"
CLIENT_ID = "test-client-id"

VALID_ISSUERS = [
    f"https://login.microsoftonline.com/{TENANT_ID}/v2.0",
    f"https://sts.windows.net/{TENANT_ID}/",
]


def _make_settings() -> Settings:
    return Settings(
        azure_tenant_id=TENANT_ID,
        azure_client_id=CLIENT_ID,
        azure_eventgrid_mqtt_host="",
        azure_eventgrid_mqtt_port=8883,
        azure_eventgrid_mqtt_client_id="",
        mqtt_qos=1,
        mqtt_response_topic="topic",
        fabric_eventhouse_query_uri="",
        fabric_eventhouse_database="",
        fabric_eventhouse_query_retries=1,
        applicationinsights_connection_string="",
        enable_docs=False,
    )


def _make_rsa_key_pair() -> tuple[RSAPrivateKey, RSAPublicKey]:
    private_key = rsa.generate_private_key(
        public_exponent=65537,
        key_size=2048,
    )
    public_key = private_key.public_key()
    return private_key, public_key


def _make_token(
    private_key: RSAPrivateKey,
    *,
    issuer: str,
    audience: str = CLIENT_ID,
    kid: str = "test-kid",
    exp_offset: int = 3600,
) -> str:
    now = int(time.time())
    payload = {
        "iss": issuer,
        "aud": audience,
        "sub": "test-user",
        "iat": now,
        "exp": now + exp_offset,
    }
    return jwt.encode(
        payload,
        private_key,
        algorithm="RS256",
        headers={"kid": kid},
    )


def _make_verifier_with_key(public_key: RSAPublicKey, kid: str = "test-kid") -> TokenVerifier:
    verifier = TokenVerifier(settings=_make_settings())
    verifier._jwks_cache = {kid: public_key}
    verifier._jwks_cache_time = time.time()
    return verifier


@pytest.mark.asyncio
@pytest.mark.parametrize("issuer", VALID_ISSUERS)
async def test_verify_accepts_valid_issuers(issuer: str) -> None:
    private_key, public_key = _make_rsa_key_pair()
    token = _make_token(private_key, issuer=issuer)
    verifier = _make_verifier_with_key(public_key)

    credentials = HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)
    claims = await verifier.verify(credentials)

    assert claims["iss"] == issuer
    assert claims["sub"] == "test-user"


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "bad_issuer",
    [
        # Prefix of v2.0 issuer — was accepted by the old startswith check, must now be rejected
        f"https://login.microsoftonline.com/{TENANT_ID}/",
        # Prefix with extra path — must be rejected
        f"https://login.microsoftonline.com/{TENANT_ID}/v2.0/extra",
        # Wrong tenant
        "https://login.microsoftonline.com/wrong-tenant/v2.0",
        # Completely unrelated issuer
        "https://evil.example.com/",
    ],
)
async def test_verify_rejects_invalid_issuers(bad_issuer: str) -> None:
    private_key, public_key = _make_rsa_key_pair()
    token = _make_token(private_key, issuer=bad_issuer)
    verifier = _make_verifier_with_key(public_key)

    credentials = HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)
    with pytest.raises(HTTPException) as exc_info:
        await verifier.verify(credentials)

    assert exc_info.value.status_code == 401


@pytest.mark.asyncio
async def test_verify_rejects_expired_token() -> None:
    private_key, public_key = _make_rsa_key_pair()
    token = _make_token(private_key, issuer=VALID_ISSUERS[0], exp_offset=-1)
    verifier = _make_verifier_with_key(public_key)

    credentials = HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)
    with pytest.raises(HTTPException) as exc_info:
        await verifier.verify(credentials)

    assert exc_info.value.status_code == 401
    assert exc_info.value.detail == "Token expired"


@pytest.mark.asyncio
async def test_verify_rejects_missing_credentials() -> None:
    verifier = TokenVerifier(settings=_make_settings())

    with pytest.raises(HTTPException) as exc_info:
        await verifier.verify(None)

    assert exc_info.value.status_code == 401
    assert exc_info.value.detail == "Missing authorization header"


@pytest.mark.asyncio
async def test_verify_rejects_malformed_token() -> None:
    verifier = TokenVerifier(settings=_make_settings())

    credentials = HTTPAuthorizationCredentials(scheme="Bearer", credentials="not.a.token")
    with pytest.raises(HTTPException) as exc_info:
        await verifier.verify(credentials)

    assert exc_info.value.status_code == 401


@pytest.mark.asyncio
async def test_verify_rejects_unknown_signing_key() -> None:
    private_key, _ = _make_rsa_key_pair()
    _, different_public_key = _make_rsa_key_pair()
    token = _make_token(private_key, issuer=VALID_ISSUERS[0], kid="unknown-kid")
    verifier = _make_verifier_with_key(different_public_key, kid="other-kid")

    credentials = HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)
    with pytest.raises(HTTPException) as exc_info:
        with patch.object(verifier, "_get_signing_keys", return_value={}):
            await verifier.verify(credentials)

    assert exc_info.value.status_code == 401
    assert exc_info.value.detail == "Unable to find signing key"
