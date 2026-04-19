import pytest
from fastapi import HTTPException

from app.validators import validate_device_name, validate_timespan


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
