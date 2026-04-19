import re

from fastapi import HTTPException

DEVICE_NAME_PATTERN = re.compile(r"^[a-zA-Z0-9-]{1,64}$")
DEVICE_NAME_REQUIRED_SUFFIX = "-vm-k3s"
TIMESPAN_PATTERN = re.compile(r"^[1-9]\d*(d|h|min|m|s)$")


def validate_device_name(device_name: str) -> str:
    if not DEVICE_NAME_PATTERN.fullmatch(device_name):
        raise HTTPException(status_code=400, detail="Invalid device name")

    if not device_name.endswith(DEVICE_NAME_REQUIRED_SUFFIX):
        raise HTTPException(status_code=400, detail="Invalid device name")

    return device_name


def validate_timespan(timespan: str) -> str:
    normalized = timespan.strip().lower()

    if not TIMESPAN_PATTERN.fullmatch(normalized):
        raise HTTPException(status_code=400, detail="Invalid timespan")

    return normalized
