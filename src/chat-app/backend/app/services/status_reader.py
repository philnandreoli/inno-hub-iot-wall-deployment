import logging
import time
from typing import Any

from azure.identity import DefaultAzureCredential
from azure.kusto.data import ClientRequestProperties, KustoClient, KustoConnectionStringBuilder
from azure.kusto.data.exceptions import KustoNetworkError
from fastapi.encoders import jsonable_encoder

from app.config import Settings
from app.validators import validate_device_name, validate_timespan

logger = logging.getLogger(__name__)


class EventhouseStatusReader:
    def __init__(self, settings: Settings) -> None:
        self.query_uri = settings.fabric_eventhouse_query_uri
        self.database = settings.fabric_eventhouse_database
        self.query_retries = settings.fabric_eventhouse_query_retries
        self.credential = DefaultAzureCredential(exclude_environment_credential=True)
        self._client: KustoClient | None = None

    def _get_client(self) -> KustoClient:
        if self._client is not None:
            return self._client

        missing = []
        if not self.query_uri:
            missing.append("FABRIC_EVENTHOUSE_QUERY_URI")
        if not self.database:
            missing.append("FABRIC_EVENTHOUSE_DATABASE")
        if missing:
            raise RuntimeError(f"Missing required environment variable(s): {', '.join(missing)}")

        kcsb = KustoConnectionStringBuilder.with_azure_token_credential(
            self.query_uri,
            self.credential,
        )
        self._client = KustoClient(kcsb)
        return self._client

    def _execute_query(self, query: str, properties: ClientRequestProperties | None = None):
        last_exc: Exception | None = None

        for attempt in range(1, self.query_retries + 1):
            try:
                client = self._get_client()
                if properties is None:
                    return client.execute(self.database, query)
                return client.execute(self.database, query, properties)
            except KustoNetworkError as exc:
                self._client = None
                last_exc = exc

                if attempt >= self.query_retries:
                    raise

                backoff_seconds = min(2 ** (attempt - 1), 5)
                logger.warning(
                    "Transient Eventhouse network error (attempt %s/%s). Retrying in %ss",
                    attempt,
                    self.query_retries,
                    backoff_seconds,
                )
                time.sleep(backoff_seconds)

        if last_exc is not None:
            raise last_exc

        raise RuntimeError("Unexpected Eventhouse execution state")

    def get_device_status(self, device_name: str) -> dict[str, Any]:
        validated_device_name = validate_device_name(device_name)
        query = "declare query_parameters(deviceName:string); get_beckhoff_last_status(deviceName)"
        properties = ClientRequestProperties()
        properties.set_parameter("deviceName", validated_device_name)

        response = self._execute_query(query, properties)
        if not response.primary_results:
            raise RuntimeError("Fabric Eventhouse query returned no result set")

        result_table = response.primary_results[0]
        if result_table.rows_count == 0:
            raise LookupError(f"No status found for device '{validated_device_name}'")

        columns = [column.column_name for column in result_table.columns]
        first_row = next(iter(result_table))
        status_record = {column: first_row[index] for index, column in enumerate(columns)}
        normalized_status_record = self._normalize_status_row(status_record)

        return {
            "deviceName": validated_device_name,
            "source": "fabric-eventhouse",
            "record": jsonable_encoder(normalized_status_record),
        }

    def get_devices_by_hub(self) -> dict[str, Any]:
        response = self._execute_query("get_beckhoff_devices_by_hub()")
        if not response.primary_results:
            raise RuntimeError("Fabric Eventhouse query returned no result set")

        result_table = response.primary_results[0]
        columns = [column.column_name for column in result_table.columns]
        rows = [
            {column: row[index] for index, column in enumerate(columns)}
            for row in result_table
        ]

        return {
            "source": "fabric-eventhouse",
            "count": len(rows),
            "devicesByHub": jsonable_encoder(rows),
        }

    def get_all_devices_status(self) -> dict[str, Any]:
        response = self._execute_query("get_beckhoff_last_status_all_hubs()")
        if not response.primary_results:
            raise RuntimeError("Fabric Eventhouse query returned no result set")

        result_table = response.primary_results[0]
        columns = [column.column_name for column in result_table.columns]
        rows = [
            {column: row[index] for index, column in enumerate(columns)}
            for row in result_table
        ]
        normalized_rows = [self._normalize_status_row(row) for row in rows]

        return {
            "source": "fabric-eventhouse",
            "count": len(normalized_rows),
            "devices": jsonable_encoder(normalized_rows),
        }

    @staticmethod
    def _first_present(row: dict[str, Any], keys: list[str]) -> Any:
        for key in keys:
            if key in row and row[key] is not None:
                return row[key]
        return None

    @staticmethod
    def _to_int_or_default(value: Any, default: int = 0) -> int:
        if value is None:
            return default
        if isinstance(value, bool):
            return int(value)
        if isinstance(value, int):
            return value
        if isinstance(value, float):
            return int(value)
        if isinstance(value, str):
            try:
                return int(value)
            except ValueError:
                return default
        return default

    def _normalize_status_row(self, row: dict[str, Any]) -> dict[str, Any]:
        normalized = dict(row)

        messages_last_24h = self._first_present(
            row,
            ["messagesLast24h", "MessagesLast24h", "messages_last_24h"],
        )
        lueze_messages_last_24h = self._first_present(
            row,
            ["luezeMessagesLast24h", "LuezeMessagesLast24h", "lueze_messages_last_24h"],
        )
        lueze_last_read_barcode = self._first_present(
            row,
            [
                "luezeLastReadBarcode",
                "luezelastReadBarcode",
                "LuezeLastReadBarcode",
                "lueze_last_read_barcode",
            ],
        )
        lueze_barcode_ingestion_time = self._first_present(
            row,
            [
                "luezeBarcodeIngestionTime",
                "LuezeBarcodeIngestionTime",
                "lueze_barcode_ingestion_time",
            ],
        )

        normalized["messagesLast24h"] = self._to_int_or_default(messages_last_24h)
        normalized["luezeMessagesLast24h"] = self._to_int_or_default(lueze_messages_last_24h)
        normalized["luezeLastReadBarcode"] = lueze_last_read_barcode
        normalized["luezelastReadBarcode"] = lueze_last_read_barcode
        normalized["luezeBarcodeIngestionTime"] = lueze_barcode_ingestion_time

        return normalized

    def _normalize_measurement_row(self, row: dict[str, Any]) -> dict[str, Any]:
        return {
            "iotInstanceName": self._first_present(row, ["iotInstanceName", "iot_instance_name"]),
            "tag": self._first_present(row, ["tag"]),
            "timestamp": self._first_present(row, ["timestamp"]),
            "value_long": self._first_present(row, ["value_long", "valueLong"]),
            "value_bool": self._first_present(row, ["value_bool", "valueBool"]),
        }

    def get_device_telemetry(self, device_name: str, timespan: str = "7d") -> dict[str, Any]:
        validated_device_name = validate_device_name(device_name)
        validated_timespan = validate_timespan(timespan)

        query = (
            "declare query_parameters(deviceName:string, queryTimespan:timespan); "
            "get_iot_measurements_by_iot_instance_name(deviceName, queryTimespan)"
        )
        properties = ClientRequestProperties()
        properties.set_parameter("deviceName", validated_device_name)
        properties.set_parameter("queryTimespan", validated_timespan)

        response = self._execute_query(query, properties)
        if not response.primary_results:
            raise RuntimeError("Fabric Eventhouse query returned no result set")

        result_table = response.primary_results[0]
        columns = [column.column_name for column in result_table.columns]
        rows = [
            {column: row[index] for index, column in enumerate(columns)}
            for row in result_table
        ]
        measurements = [self._normalize_measurement_row(row) for row in rows]

        return {
            "deviceName": validated_device_name,
            "timespan": validated_timespan,
            "source": "fabric-eventhouse",
            "count": len(measurements),
            "measurements": jsonable_encoder(measurements),
        }
