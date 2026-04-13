import json
import logging
from functools import lru_cache

import httpx

from app.config import settings
from app.schemas.instance import AioInstance
from app.services.auth import get_credential
from app.services.redis_client import get_redis_client

logger = logging.getLogger(__name__)

ARM_SCOPE = "https://management.azure.com/.default"
ARM_BASE = "https://management.azure.com"
AIO_API_VERSION = "2024-11-01"
INSTANCES_CACHE_KEY = "aio:instances"
INSTANCES_CACHE_TTL = 300  # 5 minutes


class InstancesService:
    """Discovers Azure IoT Operations instances via ARM REST API and caches in Redis."""

    def __init__(self, redis_client):
        self._redis = redis_client
        self._credential = get_credential()

    def _get_token(self) -> str:
        return self._credential.get_token(ARM_SCOPE).token

    async def list_instances(self) -> list[AioInstance]:
        try:
            cached = await self._redis.get(INSTANCES_CACHE_KEY)
            if cached:
                logger.debug("Redis cache HIT for AIO instances")
                data = json.loads(cached)
                return [AioInstance(**item) for item in data]
        except Exception as exc:
            logger.warning("Redis GET error for instances cache: %s", exc)

        instances = await self._fetch_from_arm()

        try:
            await self._redis.set(
                INSTANCES_CACHE_KEY,
                json.dumps([inst.model_dump() for inst in instances]),
                ex=INSTANCES_CACHE_TTL,
            )
            logger.info(
                "Cached %d AIO instances in Redis (TTL=%ds)",
                len(instances),
                INSTANCES_CACHE_TTL,
            )
        except Exception as exc:
            logger.warning("Redis SET error for instances cache: %s", exc)

        return instances

    async def _fetch_from_arm(self) -> list[AioInstance]:
        token = self._get_token()
        headers = {"Authorization": f"Bearer {token}"}
        timeout = httpx.Timeout(30.0)
        instances: list[AioInstance] = []

        if settings.azure_subscription_ids:
            subscription_ids = [s.strip() for s in settings.azure_subscription_ids.split(",") if s.strip()]
        else:
            try:
                subscription_ids = await self._list_subscriptions(headers)
            except Exception as exc:
                logger.error("Could not list subscriptions: %s", exc)
                return []

        async with httpx.AsyncClient(timeout=timeout) as client:
            for sub_id in subscription_ids:
                try:
                    url = (
                        f"{ARM_BASE}/subscriptions/{sub_id}/providers/"
                        f"Microsoft.IoTOperations/instances"
                        f"?api-version={AIO_API_VERSION}"
                    )
                    resp = await client.get(url, headers=headers)
                    if resp.status_code == 404:
                        continue
                    resp.raise_for_status()
                    data = resp.json()
                    for item in data.get("value", []):
                        inst = self._parse_instance(item)
                        if inst:
                            instances.append(inst)
                except Exception as exc:
                    logger.warning("Failed to list AIO instances in sub=%s: %s", sub_id, exc)

        logger.info("Discovered %d AIO instance(s)", len(instances))
        return instances

    async def _list_subscriptions(self, headers: dict) -> list[str]:
        url = f"{ARM_BASE}/subscriptions?api-version=2020-01-01"
        async with httpx.AsyncClient(timeout=httpx.Timeout(15.0)) as client:
            resp = await client.get(url, headers=headers)
            resp.raise_for_status()
            return [s["subscriptionId"] for s in resp.json().get("value", [])]

    @staticmethod
    def _parse_instance(item: dict) -> AioInstance | None:
        try:
            arm_id: str = item.get("id", "")
            parts = arm_id.split("/")
            sub_id = parts[2] if len(parts) > 2 else ""
            rg = parts[4] if len(parts) > 4 else ""
            return AioInstance(
                name=item.get("name", ""),
                resource_group=rg,
                subscription_id=sub_id,
                location=item.get("location", ""),
                description=item.get("properties", {}).get("description"),
            )
        except Exception as exc:
            logger.warning("Could not parse AIO instance: %s", exc)
            return None


@lru_cache(maxsize=1)
def get_instances_service() -> InstancesService:
    return InstancesService(redis_client=get_redis_client())
