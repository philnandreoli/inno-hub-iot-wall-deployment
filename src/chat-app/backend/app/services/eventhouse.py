import asyncio
import logging
from typing import Any

import httpx

from app.config import settings
from app.schemas.device import DeviceState

logger = logging.getLogger(__name__)


class EventHouseService:
    def __init__(self, endpoint: str | None = None):
        self.endpoint = (endpoint or settings.eventhouse_mcp_endpoint).rstrip("/")
        self.timeout = httpx.Timeout(30.0)

    async def get_devices(self) -> list[str]:
        query = "SELECT DISTINCT deviceId FROM devices"
        rows = await self._query(query)
        devices: list[str] = []
        for row in rows:
            if not isinstance(row, dict):
                continue
            lowered = {str(k).lower(): v for k, v in row.items()}
            device_id = lowered.get("deviceid") or lowered.get("device_id")
            if device_id:
                devices.append(str(device_id))
        return devices

    async def get_device_state(self, device_id: str) -> DeviceState:
        query = (
            f"SELECT TOP 1 * FROM telemetry WHERE deviceId = '{device_id}' "
            "ORDER BY timestamp DESC"
        )
        rows = await self._query(query)
        if not rows:
            return DeviceState(device_id=device_id)
        return self._to_device_state(device_id, rows[0])

    async def _query(self, query: str) -> list[dict[str, Any]]:
        if not self.endpoint:
            raise ValueError("EVENTHOUSE_MCP_ENDPOINT is not configured")

        url = f"{self.endpoint}/call-tool"
        body = {"name": "query", "arguments": {"query": query}}
        last_error: Exception | None = None

        for attempt in range(1, 4):
            try:
                async with httpx.AsyncClient(timeout=self.timeout) as client:
                    response = await client.post(url, json=body)
                    response.raise_for_status()
                    payload = response.json()
                    return self._extract_rows(payload)
            except Exception as exc:
                last_error = exc
                logger.warning("EventHouse request attempt %s failed: %s", attempt, exc)
                if attempt < 3:
                    await asyncio.sleep(0.5 * attempt)

        logger.error("EventHouse query failed after retries")
        raise RuntimeError("Failed to query EventHouse MCP") from last_error

    def _extract_rows(self, payload: Any) -> list[dict[str, Any]]:
        if isinstance(payload, list):
            return [item for item in payload if isinstance(item, dict)]

        if isinstance(payload, dict):
            candidates = [
                payload.get("rows"),
                payload.get("data"),
                payload.get("results"),
                payload.get("result"),
            ]
            for candidate in candidates:
                if isinstance(candidate, list):
                    return [item for item in candidate if isinstance(item, dict)]
                if isinstance(candidate, dict):
                    nested = candidate.get("rows") or candidate.get("data")
                    if isinstance(nested, list):
                        return [item for item in nested if isinstance(item, dict)]
            content = payload.get("content")
            if isinstance(content, list):
                for item in content:
                    if isinstance(item, dict):
                        text = item.get("text")
                        if text:
                            try:
                                import json

                                parsed = json.loads(text)
                                return self._extract_rows(parsed)
                            except Exception:
                                continue
        return []

    def _to_device_state(self, device_id: str, row: dict[str, Any]) -> DeviceState:
        lowered = {str(k).lower(): v for k, v in row.items()}

        def first(*keys: str) -> Any:
            for key in keys:
                if key in lowered:
                    return lowered[key]
            return None

        parsed_device_id = first("deviceid", "device_id")
        return DeviceState(
            device_id=str(parsed_device_id or device_id),
            online=first("online"),
            lamp=first("lamp"),
            fan=first("fan"),
            temperature=first("temperature"),
            vibration=first("vibration"),
            error_code=first("error_code", "errorcode"),
            last_updated=(
                str(first("last_updated", "timestamp", "time"))
                if first("last_updated", "timestamp", "time") is not None
                else None
            ),
            raw=row,
        )

