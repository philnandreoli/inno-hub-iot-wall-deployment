# Chat App Documentation

This folder contains the chat app backend used to send device commands through Azure Event Grid and Azure IoT Operations.

- Backend API and runtime details: `./backend/README.md`

## Command Endpoints

The backend exposes these command endpoints for device control:

- `POST /api/devices/{device_name}/commands/lamp/on` -> `{"lamp": true}`
- `POST /api/devices/{device_name}/commands/lamp/off` -> `{"lamp": false}`
- `POST /api/devices/{device_name}/commands/fan/on` -> `{"fan": 32000}`
- `POST /api/devices/{device_name}/commands/fan/off` -> `{"fan": 0}`

All commands are published to:

- `/iotoperations/{device_name}/command`

## Data Flow For fan/lamp On/Off

The command/confirmation flow is:

1. API puts payload on Azure Event Grid MQTT broker.
2. Azure IoT Operations Data Flow reads from Event Grid and puts the data on the internal Azure IoT Operations MQTT broker.
3. Azure IoT Operations MQTT broker updates the device to its new configuration.
4. Device sends a confirmation message to Azure IoT Operations MQTT broker.

Flow summary:

`API -> Azure Event Grid MQTT broker -> Azure IoT Operations Data Flow -> internal Azure IoT Operations MQTT broker -> device update -> confirmation message -> Azure IoT Operations MQTT broker`
