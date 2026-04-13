# Shared Data Contracts

Authoritative documentation for all data shapes exchanged between the frontend,
backend, and Azure services in the IoT Wall Chat application.

---

## Chat API

### `POST /api/chat` – Send a user message

**Request body**

```json
{
  "session_id": "string (uuid)",
  "message": "string"
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `session_id` | `string` (UUID v4) | Yes | Identifies the ongoing conversation |
| `message` | `string` | Yes | Natural-language message from the operator |

**Response body**

```json
{
  "session_id": "string (uuid)",
  "reply": "string",
  "tool_calls": [
    {
      "tool": "string",
      "args": {},
      "result": {}
    }
  ],
  "timestamp": "string (ISO 8601)"
}
```

| Field | Type | Description |
|---|---|---|
| `session_id` | `string` | Echoed session identifier |
| `reply` | `string` | LLM-generated response text |
| `tool_calls` | `array` | Zero or more tool invocations the LLM performed |
| `timestamp` | `string` | Server-side UTC timestamp of the response |

---

## Device Command Event (Azure Event Grid)

Published to the topic path:
`/iotoperations/{instanceName}/commands`

**Event envelope (CloudEvents 1.0)**

```json
{
  "specversion": "1.0",
  "type": "com.iotwall.device.command",
  "source": "/iotwall/chat-api",
  "id": "string (uuid)",
  "time": "string (ISO 8601)",
  "datacontenttype": "application/json",
  "data": {
    "device_id": "string",
    "command": "string",
    "parameters": {}
  }
}
```

| Field | Type | Description |
|---|---|---|
| `data.device_id` | `string` | Target device identifier in IoT Operations |
| `data.command` | `string` | Command name (e.g. `set_setpoint`, `restart`) |
| `data.parameters` | `object` | Command-specific parameter map |

---

## Device State (Eventhouse / KQL)

Queried via the Eventhouse MCP endpoint.

**State record**

```json
{
  "device_id": "string",
  "timestamp": "string (ISO 8601)",
  "property": "string",
  "value": "number | string | boolean",
  "unit": "string | null"
}
```

| Field | Type | Description |
|---|---|---|
| `device_id` | `string` | Device identifier |
| `timestamp` | `string` | Observation time (UTC) |
| `property` | `string` | Property name (e.g. `temperature`, `status`) |
| `value` | `number\|string\|boolean` | Observed value |
| `unit` | `string\|null` | Engineering unit, if applicable |

---

## Health Check

### `GET /health`

**Response**

```json
{
  "status": "ok",
  "service": "iot-wall-chat-api"
}
```
