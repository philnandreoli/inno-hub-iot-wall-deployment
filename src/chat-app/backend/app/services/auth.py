import logging
from functools import lru_cache

from azure.identity import DefaultAzureCredential

logger = logging.getLogger(__name__)


@lru_cache(maxsize=1)
def get_credential() -> DefaultAzureCredential:
    """
    Returns a cached DefaultAzureCredential instance.
    Works with Managed Identity in Azure and local dev credential fallback.
    """
    try:
        credential = DefaultAzureCredential()
        logger.info("Azure credential initialized via DefaultAzureCredential")
        return credential
    except Exception as exc:
        logger.error("Failed to initialize Azure credential: %s", exc)
        raise
