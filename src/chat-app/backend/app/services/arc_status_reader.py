import logging
from typing import Any

import httpx
from azure.identity import DefaultAzureCredential

from app.config import Settings

logger = logging.getLogger(__name__)

_ARM_BASE = "https://management.azure.com"
_HYBRID_COMPUTE_API_VERSION = "2024-05-20-preview"
_CONNECTED_CLUSTERS_API_VERSION = "2024-01-01"


class ArcStatusReader:
    def __init__(self, settings: Settings) -> None:
        self.subscription_id = settings.azure_subscription_id
        self.credential = DefaultAzureCredential(exclude_environment_credential=True)
        self._http_client = httpx.Client(timeout=30.0)

    def _auth_header(self) -> dict[str, str]:
        token = self.credential.get_token("https://management.azure.com/.default").token
        return {"Authorization": f"Bearer {token}"}

    @staticmethod
    def derive_resource_names(cluster_name: str) -> tuple[str, str, str]:
        """Derive (k8s_name, vm_name, host_name) from a K8s cluster name.

        Example: 'atl-azureiot-vm-k3s' → ('atl-azureiot-vm-k3s', 'azureiot-vm', 'azureiot')
        """
        dash_pos = cluster_name.find("-")
        if dash_pos == -1:
            raise ValueError(
                f"Cannot derive resource names: no '-' separator in cluster name {cluster_name!r}"
            )
        after_prefix = cluster_name[dash_pos + 1:]
        vm_name = after_prefix.removesuffix("-k3s")
        host_name = vm_name.removesuffix("-vm")
        return cluster_name, vm_name, host_name

    @staticmethod
    def build_resource_group(hub: str, country: str) -> str:
        """Construct the resource group name from hub and country codes."""
        return f"EXP-MFG-AIO-{hub.upper()}-{country.upper()}-RG"

    def _fetch_hybrid_compute_status(self, resource_group: str, name: str) -> str:
        url = (
            f"{_ARM_BASE}/subscriptions/{self.subscription_id}"
            f"/resourceGroups/{resource_group}"
            f"/providers/Microsoft.HybridCompute/machines/{name}"
            f"?api-version={_HYBRID_COMPUTE_API_VERSION}"
        )
        logger.debug("Fetching HybridCompute status for %s in %s", name, resource_group)
        response = self._http_client.get(url, headers=self._auth_header())
        if response.status_code == 404:
            raise LookupError(
                f"HybridCompute machine '{name}' not found in resource group '{resource_group}'"
            )
        response.raise_for_status()
        return response.json().get("properties", {}).get("status", "Unknown")

    def _fetch_k8s_status(self, resource_group: str, name: str) -> str:
        url = (
            f"{_ARM_BASE}/subscriptions/{self.subscription_id}"
            f"/resourceGroups/{resource_group}"
            f"/providers/Microsoft.Kubernetes/connectedClusters/{name}"
            f"?api-version={_CONNECTED_CLUSTERS_API_VERSION}"
        )
        logger.debug("Fetching ConnectedCluster status for %s in %s", name, resource_group)
        response = self._http_client.get(url, headers=self._auth_header())
        if response.status_code == 404:
            raise LookupError(
                f"ConnectedCluster '{name}' not found in resource group '{resource_group}'"
            )
        response.raise_for_status()
        return response.json().get("properties", {}).get("connectivityStatus", "Unknown")

    def get_arc_status(self, device_name: str, hub: str, country: str) -> dict[str, Any]:
        resource_group = self.build_resource_group(hub, country)
        k8s_name, vm_name, host_name = self.derive_resource_names(device_name)

        host_status = self._fetch_hybrid_compute_status(resource_group, host_name)
        vm_status = self._fetch_hybrid_compute_status(resource_group, vm_name)
        k8s_status = self._fetch_k8s_status(resource_group, k8s_name)

        return {
            "deviceName": device_name,
            "resourceGroup": resource_group,
            "host": {
                "resourceName": host_name,
                "resourceType": "Microsoft.HybridCompute/machines",
                "status": host_status,
            },
            "vm": {
                "resourceName": vm_name,
                "resourceType": "Microsoft.HybridCompute/machines",
                "status": vm_status,
            },
            "k8sCluster": {
                "resourceName": k8s_name,
                "resourceType": "Microsoft.Kubernetes/connectedClusters",
                "status": k8s_status,
            },
        }
