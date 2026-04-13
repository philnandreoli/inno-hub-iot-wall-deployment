# IoT Wall Chat App — Deployment & Managed Identity Guide

> **ISSUE-015** | Covers architecture, required Azure resources, environment variables,
> local development setup, DevContainer usage, Managed Identity configuration, RBAC role
> assignments, and security posture for the `src/chat-app` application.

---

## 1. Application Architecture Overview

### Stack

| Layer | Technology |
|---|---|
| **Frontend** | React 18 + Vite 5 (port 3000) |
| **Backend** | FastAPI + Uvicorn (port 5000) |
| **LLM / Chat** | Azure OpenAI (gpt-4o / gpt-4-turbo) |
| **Device Telemetry** | Fabric EventHouse via MCP REST API |
| **Device Commands** | Azure Event Grid (CloudEvents) |
| **Authentication** | `DefaultAzureCredential` (azure-identity) |

### Data Flow

```
Browser (React)
      │  HTTP/fetch  /api/*
      ▼
FastAPI Backend (port 5000)
      ├─── Azure OpenAI ─────────────────► LLM chat + tool calling
      ├─── EventHouse MCP REST ──────────► Device telemetry / KQL queries
      └─── Azure Event Grid ─────────────► Publish device commands (lamp / fan)
```

The Vite dev server proxies all `/api/*` and `/health` requests to `http://localhost:5000`,
so the browser only ever talks to the same origin on port 3000 during local development.

### Security Model

All Azure service calls use **`DefaultAzureCredential`** from the `azure-identity` SDK.
No connection strings, no SAS tokens, and no API keys are stored in code or committed to
source control. The credential chain resolves automatically based on the execution
environment (see Section 6).

---

## 2. Required Azure Resources

### Azure OpenAI Service

| Property | Value |
|---|---|
| Resource type | `Microsoft.CognitiveServices/accounts` (kind: OpenAI) |
| Model deployment | `gpt-4o` or `gpt-4-turbo` (must support function/tool calling) |
| Required RBAC role | **Cognitive Services OpenAI User** |
| Assigned to | Managed Identity principal (or developer's Entra ID for local dev) |

### Fabric EventHouse (MCP REST)

| Property | Value |
|---|---|
| Interface | MCP REST API (`POST {endpoint}/call-tool`) |
| Query tool name | `query` |
| Expected tables | `devices` (columns: `deviceId`), `telemetry` (columns: `deviceId`, `timestamp`, `lamp`, `fan`, `temperature`, `vibration`, `online`, `error_code`) |
| Auth | Bearer token obtained via `DefaultAzureCredential` (passed in HTTP header by the MCP client or via the endpoint's own auth layer) |
| Required permission | **Viewer** or **Contributor** on the EventHouse workspace |

> The backend POSTs `{ "name": "query", "arguments": { "query": "<KQL/SQL>" } }` to
> `EVENTHOUSE_MCP_ENDPOINT/call-tool`. The service must be network-reachable from wherever
> the backend runs.

### Azure Event Grid MQTT Broker

| Property | Value |
|---|---|
| Resource type | `Microsoft.EventGrid/namespaces` (EventGrid Namespace with MQTT broker enabled) |
| MQTT hostname | `<namespace>.<region>-1.ts.eventgrid.azure.net` |
| Port | `8883` (MQTTS / TLS) |
| Topic convention | `iotoperations/{instanceName}/commands/{deviceId}` (derived from `INSTANCE_NAME`) |
| Auth | Azure AD access token (`DefaultAzureCredential` scope: `https://eventgrid.azure.net/.default`) |
| Required RBAC role | **EventGrid Data Sender** |
| Assigned to | Managed Identity principal (or developer's Entra ID for local dev) |

> The backend connects to the MQTT broker using `paho-mqtt`, authenticating with
> a short-lived Azure AD bearer token as the MQTT password (username = broker hostname).
> No SAS keys or connection strings are used.

---

## 3. Required Environment Variables

Copy `src/chat-app/backend/.env.example` to `src/chat-app/backend/.env` and populate all
values before starting the backend.

| Variable | Description | Example |
|---|---|---|
| `AZURE_OPENAI_ENDPOINT` | Azure OpenAI resource endpoint | `https://{name}.openai.azure.com/` |
| `AZURE_OPENAI_DEPLOYMENT` | Deployment name for the chat model | `gpt-4o` |
| `EVENTHOUSE_MCP_ENDPOINT` | EventHouse MCP REST base URL | `https://{host}/v1` |
| `EVENTGRID_MQTT_HOSTNAME` | EventGrid Namespace MQTT broker hostname | `{namespace}.{region}-1.ts.eventgrid.azure.net` |
| `EVENTGRID_MQTT_PORT` | MQTT broker port (TLS) | `8883` |
| `INSTANCE_NAME` | IoT Operations instance name | `myinstance` |
| `STATE_CACHE_TTL_SECONDS` | Device state cache TTL in seconds (5–30) | `15` |

> **`STATE_CACHE_TTL_SECONDS`** defaults to `15` if not set. Tune it to balance freshness
> against EventHouse query volume.

---

## 4. Local Development Setup (non-DevContainer)

### Prerequisites

- Python 3.11+
- Node.js 20+
- Azure CLI (`az` version 2.55+)

### Step-by-step

```bash
# 1. Clone the repository
git clone https://github.com/<org>/inno-hub-iot-wall-deployment.git
cd inno-hub-iot-wall-deployment

# 2. Set up Python virtual environment and install backend dependencies
cd src/chat-app/backend
python -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r requirements.txt

# 3. Install frontend npm packages
cd ../frontend
npm install

# 4. Create .env from the example and fill in all values
cd ../backend
cp .env.example .env
# Edit .env with your Azure resource endpoints and configuration values

# 5. Log in with Azure CLI so DefaultAzureCredential can resolve your identity
az login
# If your subscription is in a specific tenant:
# az login --tenant <tenant-id>

# 6. Start the backend (Terminal 1)
cd src/chat-app/backend
source .venv/bin/activate
uvicorn app.main:app --reload --port 5000

# 7. Start the frontend (Terminal 2)
cd src/chat-app/frontend
npm run dev

# 8. Open the app
# http://localhost:3000
```

### Verify the backend is healthy

```bash
curl http://localhost:5000/health
# Expected: {"status":"ok"}
```

### Verify the OpenAPI docs

Navigate to `http://localhost:5000/docs` to see the interactive API explorer.

---

## 5. DevContainer Setup

The repository ships with a fully configured DevContainer at `.devcontainer/devcontainer.json`
that works identically in **VS Code local Dev Containers** and **GitHub Codespaces**.

### VS Code Local Dev Containers

#### Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (running)
- [Visual Studio Code](https://code.visualstudio.com/)
- [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) (`ms-vscode-remote.remote-containers`)

#### Steps

1. Open the repository root in VS Code.
2. When prompted *"Folder contains a Dev Container configuration"*, click **Reopen in Container**.
   Alternatively, open the Command Palette (`Ctrl/Cmd+Shift+P`) and run
   **Dev Containers: Reopen in Container**.
3. VS Code builds the container image (first run takes a few minutes).
4. The `postCreateCommand` (`.devcontainer/post-create.sh`) runs automatically and:
   - Installs Python backend dependencies (`pip install -r requirements.txt`)
   - Installs Node frontend dependencies (`npm install`)
   - Writes `src/chat-app/backend/.env` from any environment variables already set on the host

5. Configure environment variables using **one of these two methods**:

   **Method A — Host environment variables (recommended)**

   Set the variables in your host shell before opening VS Code.  The DevContainer maps them
   via `${localEnv:…}` in `devcontainer.json` and the `post-create.sh` script writes them
   into `.env` automatically:

   ```bash
   export AZURE_OPENAI_ENDPOINT="https://{name}.openai.azure.com/"
   export AZURE_OPENAI_DEPLOYMENT="gpt-4o"
   export EVENTHOUSE_MCP_ENDPOINT="https://{host}/v1"
   export EVENTGRID_MQTT_HOSTNAME="{namespace}.{region}-1.ts.eventgrid.azure.net"
   export INSTANCE_NAME="myinstance"
   ```

   **Method B — `.env` file inside the container**

   Edit the auto-generated file in the integrated terminal after the container starts
   (the file is git-ignored):

   ```bash
   # .env is created automatically by post-create.sh — just fill in the blank values
   nano src/chat-app/backend/.env
   ```

6. Authenticate with Azure from the integrated terminal:

   ```bash
   az login
   ```

7. Start the backend and frontend from separate integrated terminals:

   ```bash
   # Terminal 1 — Backend
   cd src/chat-app/backend && uvicorn app.main:app --reload --port 5000

   # Terminal 2 — Frontend
   cd src/chat-app/frontend && npm run dev
   ```

Ports 3000 and 5000 are automatically forwarded and VS Code will notify you when they open.

---

### GitHub Codespaces

Codespaces uses the same `devcontainer.json` — no separate configuration is needed.

#### Prerequisites

- A GitHub account with access to this repository
- The repository visible at `github.com/<org>/inno-hub-iot-wall-deployment`

#### Configuring secrets

Codespaces secrets are injected into the container as environment variables.  Set the
following secrets **before** creating a Codespace so that `post-create.sh` can write
them to `.env` automatically:

| Secret name | Where to set |
|---|---|
| `AZURE_OPENAI_ENDPOINT` | [User secrets](https://github.com/settings/codespaces) or repo → Settings → Secrets → Codespaces |
| `AZURE_OPENAI_DEPLOYMENT` | Same as above |
| `EVENTHOUSE_MCP_ENDPOINT` | Same as above |
| `EVENTGRID_MQTT_HOSTNAME` | Same as above |
| `EVENTGRID_MQTT_PORT` | Same as above (optional; defaults to `8883`) |
| `INSTANCE_NAME` | Same as above |

#### Steps

1. Navigate to the repository on GitHub.
2. Click **Code → Codespaces → Create codespace on `<branch>`**.
3. Wait for the Codespace to build (first run ~3–5 minutes).
4. `post-create.sh` runs automatically and writes `.env` from the secrets you configured.
5. Authenticate with Azure CLI from the integrated terminal:

   ```bash
   az login --use-device-code
   # Follow the device-code flow — works inside any browser-accessible Codespace
   ```

6. Start the services:

   ```bash
   # Terminal 1 — Backend
   cd src/chat-app/backend && uvicorn app.main:app --reload --port 5000

   # Terminal 2 — Frontend
   cd src/chat-app/frontend && npm run dev
   ```

7. Codespaces automatically forwards ports 3000 and 5000.  Click the notification or open
   the **Ports** panel and click the globe icon next to port 3000 to open the app.

---

## 6. Managed Identity vs Local Development

### How `DefaultAzureCredential` Works

`DefaultAzureCredential` walks a chain of credential providers in order, using the first
one that succeeds:

```
EnvironmentCredential          → AZURE_CLIENT_ID / AZURE_CLIENT_SECRET / AZURE_TENANT_ID
WorkloadIdentityCredential     → Kubernetes / AKS federated identity
ManagedIdentityCredential      → Azure VM / Container App / App Service MSI endpoint
SharedTokenCacheCredential     → VS Code cached token
VisualStudioCodeCredential     → VS Code Azure Account extension
AzureCliCredential             → Token from `az login` session
AzurePowerShellCredential      → Token from `Connect-AzAccount` session
AzureDeveloperCliCredential    → Token from `azd auth login` session
```

No configuration is required — the correct provider is selected automatically.

### Credential Resolution by Environment

| Environment | Credential Flow |
|---|---|
| **Local Dev** | `AzureCliCredential` — token from `az login` session |
| **DevContainer (local)** | `AzureCliCredential` — `az login` run inside the container, or host env vars forwarded via `${localEnv:…}` → `EnvironmentCredential` |
| **GitHub Codespaces** | `AzureCliCredential` — `az login --use-device-code` inside the Codespace terminal |
| **Azure Hosted** (VM, AKS, Container Apps) | `ManagedIdentityCredential` — MSI endpoint resolves the system-assigned or user-assigned identity automatically |

### Why No Connection Strings or Keys Are Needed

- Azure OpenAI, EventGrid, and Fabric all support **Microsoft Entra ID (Azure AD)** token
  authentication.
- `DefaultAzureCredential` acquires a short-lived bearer token scoped to each service and
  refreshes it automatically before expiry.
- This eliminates the risk of long-lived credentials being leaked through source control,
  logs, or environment variable dumps.

### Assigning Required Roles to a Managed Identity

See Section 7 for the exact `az role assignment create` commands.

---

## 7. Azure RBAC Role Assignments

Run these commands once per environment to grant your Managed Identity the minimum
permissions it needs.

```bash
# ── Variables ────────────────────────────────────────────────────────────────
SUBSCRIPTION_ID="<your-subscription-id>"
RESOURCE_GROUP="<your-resource-group>"
MI_NAME="<your-managed-identity-name>"
AOAI_ACCOUNT_NAME="<your-openai-account-name>"
EG_NAMESPACE_NAME="<your-eventgrid-namespace-name>"

# ── Get the Managed Identity's principal ID ───────────────────────────────────
PRINCIPAL_ID=$(az identity show \
  --name "$MI_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query principalId \
  --output tsv)

echo "Principal ID: $PRINCIPAL_ID"

# ── Azure OpenAI ─────────────────────────────────────────────────────────────
az role assignment create \
  --role "Cognitive Services OpenAI User" \
  --assignee "$PRINCIPAL_ID" \
  --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.CognitiveServices/accounts/${AOAI_ACCOUNT_NAME}"

# ── Azure Event Grid Namespace (MQTT broker) ──────────────────────────────────
az role assignment create \
  --role "EventGrid Data Sender" \
  --assignee "$PRINCIPAL_ID" \
  --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/namespaces/${EG_NAMESPACE_NAME}"
```

> **Note:** Role assignment propagation can take 2–5 minutes. If you receive a `403`
> immediately after assignment, wait a moment and retry.

For **Fabric EventHouse**, permissions are managed through the Fabric workspace UI:
navigate to the workspace → Settings → Permissions → Add member, and grant the Managed
Identity at least **Viewer** access.

---

## 8. Troubleshooting

### `DefaultAzureCredential` authentication failed

**Symptoms:** `azure.core.exceptions.ClientAuthenticationError` in backend logs.

**Solutions:**
- Run `az login` (or `az login --tenant <tenant-id>` for a specific tenant).
- Confirm the correct subscription is active: `az account show`.
- If running in a container without host env pass-through, run `az login` inside the container.

### `403 Forbidden` on Azure OpenAI endpoint

**Symptoms:** Chat requests return a 403 or `PermissionDenied` error.

**Solutions:**
- Verify the **Cognitive Services OpenAI User** role is assigned to the principal making
  the request (your Entra ID user for local dev, Managed Identity for hosted).
- Check the role is scoped to the correct OpenAI account resource.
- Wait up to 5 minutes for RBAC propagation if the role was just assigned.

### `403 Forbidden` on EventGrid endpoint

**Symptoms:** Command publish returns a 403 error.

**Solutions:**
- Verify the **EventGrid Data Sender** role is assigned on the correct topic resource.
- Confirm `EVENTGRID_ENDPOINT` points to the topic endpoint, not the namespace root.

### EventHouse MCP timeout

**Symptoms:** Device state shows "State unavailable"; backend logs show
`Failed to query EventHouse MCP` after retries.

**Solutions:**
- Verify `EVENTHOUSE_MCP_ENDPOINT` is set and ends without a trailing slash (the service
  appends `/call-tool` automatically).
- Confirm the endpoint is network-reachable from your dev machine or container.
- Check Fabric workspace permissions for the authenticating identity.

### CORS error in browser

**Symptoms:** Browser console shows `Cross-Origin Request Blocked` or similar.

**Solutions:**
- Confirm the backend is running on port 5000 (`uvicorn app.main:app --reload --port 5000`).
- The Vite proxy forwards `/api/*` and `/health` to `http://localhost:5000`.
  If the backend port changes, update `vite.config.js` accordingly.
- CORS is only an issue if you access the backend directly (not via the Vite proxy).

### Cannot connect to backend

**Symptoms:** Frontend shows a network error banner for all API calls.

**Solutions:**
- Confirm the backend process is running and listening on port 5000.
- Check `vite.config.js` — the proxy target must match the backend port.
- In the DevContainer, verify port 5000 is forwarded (VS Code Ports panel).

### `.env` values not picked up

**Symptoms:** Settings show empty strings; services raise `ValueError: … is not configured`.

**Solutions:**
- Ensure `.env` exists at `src/chat-app/backend/.env` (not at the repo root).
- The backend loads `.env` relative to its working directory. Always start `uvicorn` from
  `src/chat-app/backend/`.

---

## 9. Security Posture

| Principle | Implementation |
|---|---|
| **No connection strings in code** | All service clients are constructed with token credentials only |
| **No API keys in code** | `DefaultAzureCredential` acquires short-lived tokens; no static keys in source |
| **No secrets in config files** | `.env` is listed in `.gitignore` and must never be committed |
| **Environment-driven credentials** | Auth chain resolves from `az login`, Managed Identity, or Workload Identity depending on environment |
| **Production auth path is Managed Identity** | System-assigned or user-assigned MI on the hosting compute; zero secret management overhead |
| **Least-privilege RBAC** | Only two roles required: `Cognitive Services OpenAI User` and `EventGrid Data Sender` |
| **Token scoping** | Each `azure-identity` credential scope is specific to the target service (OpenAI, EventGrid) |

> **Reminder:** Never add `.env` or any file containing real credentials to source control.
> The `.env.example` file contains only placeholder values and is safe to commit.
