import logging
from typing import Any

from azure.identity import DefaultAzureCredential
from azure.mgmt.compute import ComputeManagementClient

from app.config import Settings

logger = logging.getLogger(__name__)

# Fields checked (in priority order) to identify the Azure VM name from a status record
_VM_IDENTIFIER_FIELDS = (
    "vmName",
    "VmName",
    "vm_name",
    "hostName",
    "HostName",
    "host_name",
    "instanceName",
    "InstanceName",
    "instance_name",
)


class AzureVmStatusReader:
    def __init__(self, settings: Settings) -> None:
        self.subscription_id = settings.azure_subscription_id
        self.resource_group = settings.azure_resource_group
        self._credential = DefaultAzureCredential()
        self._client: ComputeManagementClient | None = None

    def _is_configured(self) -> bool:
        return bool(self.subscription_id and self.resource_group)

    def _get_client(self) -> ComputeManagementClient:
        if self._client is None:
            self._client = ComputeManagementClient(self._credential, self.subscription_id)
        return self._client

    @staticmethod
    def extract_vm_identifier(record: dict[str, Any]) -> str | None:
        """Return the first non-empty VM identifier found in a status record."""
        for field in _VM_IDENTIFIER_FIELDS:
            value = record.get(field)
            if value and isinstance(value, str) and value.strip():
                return value.strip()
        return None

    def get_vm_status(self, device_name: str, record: dict[str, Any]) -> dict[str, Any]:
        """
        Return the Azure VM power state for the device identified by *record*.

        Returns ``{"azureStatus": "Not Implemented", ...}`` when:
        - the record contains no recognised VM identifier field, or
        - the service is not configured (missing subscription / resource-group).
        """
        vm_identifier = self.extract_vm_identifier(record)

        if not vm_identifier or not self._is_configured():
            return {
                "deviceName": device_name,
                "azureStatus": "Not Implemented",
                "identifier": vm_identifier,
            }

        try:
            client = self._get_client()
            vm = client.virtual_machines.get(
                self.resource_group,
                vm_identifier,
                expand="instanceView",
            )
            statuses = vm.instance_view.statuses if vm.instance_view else []
            power_state = next(
                (s.display_status for s in statuses if s.code and s.code.startswith("PowerState/")),
                "Unknown",
            )
        except Exception:
            logger.exception(
                "Failed to retrieve Azure VM status for device '%s' (VM identifier: '%s')",
                device_name,
                vm_identifier,
            )
            raise

        return {
            "deviceName": device_name,
            "azureStatus": power_state,
            "identifier": vm_identifier,
        }
