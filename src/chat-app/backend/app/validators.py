import re
from datetime import datetime

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


MAX_DATE_RANGE_DAYS = 60


def validate_date_range(start_date: datetime | None, end_date: datetime | None) -> tuple[datetime | None, datetime | None]:
    if (start_date is None) != (end_date is None):
        raise HTTPException(
            status_code=400,
            detail="Both startDate and endDate are required when filtering by date range",
        )

    if start_date is not None and end_date is not None and start_date >= end_date:
        raise HTTPException(status_code=400, detail="startDate must be before endDate")

    if start_date is not None and end_date is not None:
        delta = end_date - start_date
        if delta.days > MAX_DATE_RANGE_DAYS:
            raise HTTPException(
                status_code=400,
                detail=f"Date range cannot exceed {MAX_DATE_RANGE_DAYS} days",
            )

    return start_date, end_date
