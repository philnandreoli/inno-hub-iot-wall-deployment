import json
import time
from typing import Any

import jwt
import requests
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.config import Settings

bearer_scheme = HTTPBearer(auto_error=False)


class TokenVerifier:
    def __init__(self, settings: Settings) -> None:
        self._client_id = settings.azure_client_id
        self._issuers = [
            f"https://login.microsoftonline.com/{settings.azure_tenant_id}/v2.0",
            f"https://sts.windows.net/{settings.azure_tenant_id}/",
        ]
        self._jwks_url = (
            f"https://login.microsoftonline.com/{settings.azure_tenant_id}/discovery/v2.0/keys"
        )
        self._jwks_cache: dict[str, Any] | None = None
        self._jwks_cache_time = 0.0
        self._jwks_cache_ttl = 3600

    def _get_signing_keys(self) -> dict[str, Any]:
        now = time.time()
        if self._jwks_cache and (now - self._jwks_cache_time) < self._jwks_cache_ttl:
            return self._jwks_cache

        response = requests.get(self._jwks_url, timeout=10)
        response.raise_for_status()
        jwks = response.json()

        keys: dict[str, Any] = {}
        for key_data in jwks.get("keys", []):
            kid = key_data.get("kid")
            if kid:
                keys[kid] = jwt.algorithms.RSAAlgorithm.from_jwk(json.dumps(key_data))

        self._jwks_cache = keys
        self._jwks_cache_time = now
        return keys

    async def verify(
        self,
        credentials: HTTPAuthorizationCredentials | None,
    ) -> dict[str, Any]:
        if not self._client_id:
            raise HTTPException(
                status_code=500,
                detail="Server authentication is not configured",
            )

        if credentials is None:
            raise HTTPException(status_code=401, detail="Missing authorization header")

        token = credentials.credentials
        try:
            unverified_header = jwt.get_unverified_header(token)
        except jwt.DecodeError as exc:
            raise HTTPException(status_code=401, detail="Invalid token") from exc

        kid = unverified_header.get("kid")
        keys = self._get_signing_keys()
        public_key = keys.get(kid)

        if public_key is None:
            self._jwks_cache_time = 0
            keys = self._get_signing_keys()
            public_key = keys.get(kid)

        if public_key is None:
            raise HTTPException(status_code=401, detail="Unable to find signing key")

        try:
            claims = jwt.decode(
                token,
                public_key,
                algorithms=["RS256"],
                audience=[self._client_id, f"api://{self._client_id}"],
                issuer=self._issuers,
            )
        except jwt.ExpiredSignatureError as exc:
            raise HTTPException(status_code=401, detail="Token expired") from exc
        except jwt.InvalidTokenError as exc:
            raise HTTPException(status_code=401, detail="Invalid token") from exc

        return claims
