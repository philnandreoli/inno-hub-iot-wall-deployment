from datetime import datetime, timezone

import pytest
from fastapi import HTTPException

from app.validators import validate_date_range, validate_device_name, validate_timespan


def test_validate_device_name_accepts_expected_pattern() -> None:
    assert validate_device_name("beckhoff-01-vm-k3s") == "beckhoff-01-vm-k3s"


@pytest.mark.parametrize(
    "device_name",
    [
        "",
        "bad name-vm-k3s",
        "bad_name-vm-k3s",
        "x" * 65,
        "device-without-suffix",
    ],
)
def test_validate_device_name_rejects_invalid_values(device_name: str) -> None:
    with pytest.raises(HTTPException) as exc_info:
        validate_device_name(device_name)

    assert exc_info.value.status_code == 400
    assert exc_info.value.detail == "Invalid device name"


@pytest.mark.parametrize("timespan", ["7d", "30min", "1h", "15m", "90s", " 7D "])
def test_validate_timespan_accepts_supported_values(timespan: str) -> None:
    assert validate_timespan(timespan)


@pytest.mark.parametrize("timespan", ["0h", "-1h", "7", "min", "1hour", "bad-value"])
def test_validate_timespan_rejects_invalid_values(timespan: str) -> None:
    with pytest.raises(HTTPException) as exc_info:
        validate_timespan(timespan)

    assert exc_info.value.status_code == 400
    assert exc_info.value.detail == "Invalid timespan"


def test_validate_date_range_accepts_valid_range() -> None:
    start_date = datetime(2026, 4, 24, 0, 0, tzinfo=timezone.utc)
    end_date = datetime(2026, 4, 25, 0, 0, tzinfo=timezone.utc)

    assert validate_date_range(start_date, end_date) == (start_date, end_date)


@pytest.mark.parametrize(
    "start_date,end_date",
    [
        (datetime(2026, 4, 24, 0, 0, tzinfo=timezone.utc), None),
        (None, datetime(2026, 4, 25, 0, 0, tzinfo=timezone.utc)),
    ],
)
def test_validate_date_range_rejects_partial_range(
    start_date: datetime | None,
    end_date: datetime | None,
) -> None:
    with pytest.raises(HTTPException) as exc_info:
        validate_date_range(start_date, end_date)

    assert exc_info.value.status_code == 400
    assert exc_info.value.detail == "Both startDate and endDate are required when filtering by date range"


def test_validate_date_range_rejects_invalid_order() -> None:
    start_date = datetime(2026, 4, 25, 0, 0, tzinfo=timezone.utc)
    end_date = datetime(2026, 4, 24, 0, 0, tzinfo=timezone.utc)

    with pytest.raises(HTTPException) as exc_info:
        validate_date_range(start_date, end_date)

    assert exc_info.value.status_code == 400
    assert exc_info.value.detail == "startDate must be before endDate"


def test_validate_date_range_rejects_range_exceeding_max_days() -> None:
    start_date = datetime(2026, 1, 1, 0, 0, tzinfo=timezone.utc)
    end_date = datetime(2026, 4, 1, 0, 0, tzinfo=timezone.utc)  # 90 days

    with pytest.raises(HTTPException) as exc_info:
        validate_date_range(start_date, end_date)

    assert exc_info.value.status_code == 400
    assert "60 days" in exc_info.value.detail
