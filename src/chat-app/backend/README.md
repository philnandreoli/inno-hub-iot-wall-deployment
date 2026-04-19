# IoT Command Backend (Python)

This backend exposes an HTTP API that publishes MQTT commands to Azure Event Grid MQTT topics.

Authentication uses Azure identity credentials (for local dev: `az login`) and MQTT v5 `OAUTH2-JWT` authentication data.

Each published message includes MQTT v5 properties:
- `payload-format-indicator: 1`
- `content-type: application/json`
- `correlation-data: <unique GUID per message>`
- `message-expiry-interval: 60` (default, configurable via `MQTT_MESSAGE_EXPIRY_INTERVAL`)

## Endpoints

- `POST /api/devices/{device_name}/commands/lamp/on`
  No request body.
  Published payload: `{"lamp": true}`

- `POST /api/devices/{device_name}/commands/lamp/off`
  No request body.
  Published payload: `{"lamp": false}`

- `POST /api/devices/{device_name}/commands/fan/on`
  No request body.
  Published payload: `{"fan": 32000}`

- `POST /api/devices/{device_name}/commands/fan/off`
  No request body.
  Published payload: `{"fan": 0}`

All commands publish to topic: `/iotoperations/{device_name}/command`.

- `GET /api/devices/{device_name}/commands/status`
  Returns the latest status record for the specified IoT device from Microsoft Fabric Eventhouse.

- `GET /api/devices/by-hub`
  Returns all Beckhoff devices grouped by hub from Microsoft Fabric Eventhouse.

- `GET /api/devices/commands/status`
  Returns the latest status for all devices across all hubs from Microsoft Fabric Eventhouse.

## Command Data Flow (fan/lamp on/off)

The `lamp/on`, `lamp/off`, `fan/on`, and `fan/off` APIs follow this end-to-end path:

1. The API publishes the command payload to the Azure Event Grid MQTT broker.
2. Azure IoT Operations Data Flow reads that command from Event Grid.
3. Data Flow republishes the command to the internal Azure IoT Operations MQTT broker.
4. The Azure IoT Operations MQTT broker delivers the command to the target device so it applies the new configuration.
5. The device publishes a confirmation message back to the Azure IoT Operations MQTT broker.

Flow summary:

`API -> Azure Event Grid MQTT broker -> Azure IoT Operations Data Flow -> internal Azure IoT Operations MQTT broker -> device applies config -> confirmation message -> Azure IoT Operations MQTT broker`

The API sets MQTT `ResponseTopic` from `MQTT_RESPONSE_TOPIC` (default: `azure-iot-operations/responses/beckhoff-controller`) so downstream components can route command confirmations.

## Setup

1. Create a virtual environment and install dependencies:
   ```bash
   cd src/chat-app/backend
   pip install -r requirements.txt
   ```
2. Configure environment variables:
   ```bash
   cp .env.example .env
   ```
    Fill in `AZURE_EVENTGRID_MQTT_HOST`, `FABRIC_EVENTHOUSE_QUERY_URI`, and `FABRIC_EVENTHOUSE_DATABASE`.

## Fabric Eventhouse query settings

- `FABRIC_EVENTHOUSE_QUERY_URI`
  Eventhouse KQL query endpoint (for example: `https://<eventhouse>.<region>.kusto.windows.net`).

- `FABRIC_EVENTHOUSE_DATABASE`
  Eventhouse database name.

Status endpoint query used by the backend:

`get_beckhoff_last_status('<device_name>')`

## Azure prerequisites

1. Ensure your Event Grid namespace is configured for Microsoft Entra JWT authentication.
2. Grant your signed-in identity (or workload identity in Azure) the `EventGrid TopicSpaces Publisher` role at the target Topic Space or Namespace scope.

Notes:
- Token audience for this flow is `https://eventgrid.azure.net/`.
- The service requests token scope `https://eventgrid.azure.net/.default`.
- `AZURE_EVENTGRID_MQTT_CLIENT_ID` is optional. If omitted, a random MQTT client ID is generated.

## Local login

Authenticate locally with:

```bash
az login
```

## Run

```bash
uvicorn main:app --host 0.0.0.0 --port ${PORT:-5000}
```

## Example calls

```bash
curl -X POST "http://localhost:8080/api/devices/device123/commands/lamp/on"

curl -X POST "http://localhost:8080/api/devices/device123/commands/lamp/off"

curl -X POST "http://localhost:8080/api/devices/device123/commands/fan/on"

curl -X POST "http://localhost:8080/api/devices/device123/commands/fan/off"
```
